import Foundation
import os
import OSLog
import WheedgetsCore

/// Reads finger positions from the trackpad through Apple's private
/// MultitouchSupport framework (what BetterTouchTool and friends use).
///
/// Read-only: it observes raw finger contacts beside the normal event flow,
/// so the pointer, scrolling and every gesture keep working untouched.
/// Loaded at runtime; if a macOS update removes it, the feature reports
/// itself unavailable instead of crashing.
@MainActor
enum MultitouchTrackpad {
    private typealias CreateList = @convention(c) () -> Unmanaged<CFArray>?
    fileprivate typealias FrameCallback = @convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer?, Int32, Double, Int32) -> Int32
    private typealias Register = @convention(c) (UnsafeMutableRawPointer?, FrameCallback) -> Void
    private typealias DeviceCall = @convention(c) (UnsafeMutableRawPointer?, Int32) -> Void

    private struct API {
        let createList: CreateList
        let register: Register
        let unregister: Register
        let start: DeviceCall
        let stop: DeviceCall
    }

    private static let api: API? = {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_NOW),
              let createList = dlsym(handle, "MTDeviceCreateList"),
              let register = dlsym(handle, "MTRegisterContactFrameCallback"),
              let unregister = dlsym(handle, "MTUnregisterContactFrameCallback"),
              let start = dlsym(handle, "MTDeviceStart"),
              let stop = dlsym(handle, "MTDeviceStop") else {
            Logger.input.error("MultitouchSupport is unavailable")
            return nil
        }
        return API(
            createList: unsafeBitCast(createList, to: CreateList.self),
            register: unsafeBitCast(register, to: Register.self),
            unregister: unsafeBitCast(unregister, to: Register.self),
            start: unsafeBitCast(start, to: DeviceCall.self),
            stop: unsafeBitCast(stop, to: DeviceCall.self)
        )
    }()

    enum Mode: Equatable, Sendable {
        /// Finger motion around the center drives the spinner.
        case spinner(sensitivity: Double)
        /// Fingers hit drum zones; `reportsTaps` sends a hit per touchdown.
        case drums(reportsTaps: Bool)
        /// Records one finger's path, from touchdown to lift (drawing a zone).
        case tracing
    }

    private static var devices: [AnyObject] = []
    /// Sessions by owner; the last one is live. A session started on top of
    /// another (drawing a zone while the drums play) pauses it, and stopping
    /// it resumes the one below.
    private static var sessions: [(owner: String, mode: Mode)] = []

    /// Called on the main thread when fingers start moving, so a resting
    /// spinner can wake up its animation.
    static var onActivity: (() -> Void)?
    /// Called on the main thread with each batch of finger touchdowns (drums).
    static var onHits: (([TrackpadHitDetector.Hit]) -> Void)?

    static var isAvailable: Bool { api != nil }
    static var isRunning: Bool { !devices.isEmpty }

    /// Starts (or updates) `owner`'s session and makes it the live one.
    @discardableResult
    static func start(_ mode: Mode, owner: String) -> Bool {
        guard let api else { return false }
        sessions.removeAll { $0.owner == owner }
        sessions.append((owner, mode))
        activate(mode)
        guard devices.isEmpty else { return true }
        let list = (api.createList()?.takeRetainedValue() as? [AnyObject]) ?? []
        for device in list {
            let pointer = Unmanaged.passUnretained(device).toOpaque()
            api.register(pointer, contactFrame)
            api.start(pointer, 0)
        }
        devices = list
        return !list.isEmpty
    }

    /// Ends `owner`'s session; the session below it, if any, resumes.
    static func stop(owner: String) {
        guard let api, sessions.contains(where: { $0.owner == owner }) else { return }
        sessions.removeAll { $0.owner == owner }
        if let resumed = sessions.last {
            activate(resumed.mode)
            return
        }
        for device in devices {
            let pointer = Unmanaged.passUnretained(device).toOpaque()
            api.unregister(pointer, contactFrame)
            api.stop(pointer, 0)
        }
        devices = []
        shared.withLock { $0.reset() }
    }

    private static func activate(_ mode: Mode) {
        shared.withLock {
            $0.reset()
            $0.mode = mode
            if case .spinner(let sensitivity) = mode { $0.drive.sensitivity = sensitivity }
        }
    }

    /// The path traced so far, and whether the finger has lifted.
    static func tracedPath() -> (points: [ZonePoint], finished: Bool) {
        shared.withLock { ($0.trace, $0.traceFinished) }
    }

    static func setSensitivity(_ sensitivity: Double) {
        shared.withLock { $0.drive.sensitivity = sensitivity }
    }

    struct Gesture {
        /// The moving fingers' speed, or nil if none move.
        var speed: Double?
        var isFlicking = false
        /// 0…1: how firmly resting fingers hold the spinner.
        var hold = 0.0
        /// Fingers landed and stayed put.
        var isGrabbing = false
    }

    static func currentGesture() -> Gesture {
        shared.withLock { state in
            // No frame for a moment means the fingers lifted without a final frame.
            guard ProcessInfo.processInfo.systemUptime - state.lastFrame < 0.1 else { return Gesture() }
            guard case .spinner = state.mode else { return Gesture() }
            return Gesture(
                speed: state.drive.target,
                isFlicking: state.drive.isFlicking,
                hold: state.drive.holdStrength,
                isGrabbing: state.drive.isGrabbing
            )
        }
    }

    /// Fingers on the pad right now, for placing a click.
    static func touchingContacts() -> [TrackpadHitDetector.Contact] {
        shared.withLock { state in
            ProcessInfo.processInfo.systemUptime - state.lastFrame < 0.1 ? state.touching : []
        }
    }

    fileprivate static func handleHits(_ hits: [TrackpadHitDetector.Hit]) {
        onHits?(hits)
    }

    fileprivate static func handleActivity() {
        shared.withLock { $0.wakePending = false }
        onActivity?()
    }
}

/// Written by the multitouch thread, read by the main thread.
private struct SharedState: Sendable {
    var mode: MultitouchTrackpad.Mode = .drums(reportsTaps: false)
    var drive = TrackpadDrive()
    var hits = TrackpadHitDetector()
    var touching: [TrackpadHitDetector.Contact] = []
    var lastFrame = 0.0
    var wakePending = false
    var trace: [ZonePoint] = []
    var traceFinger: Int32?
    var traceFinished = false
    /// Fingers already down when tracing began (the one that clicked "Draw Zone").
    var traceIgnored: Set<Int32>?

    mutating func reset() {
        drive.reset()
        hits.reset()
        touching.removeAll()
        wakePending = false
        trace.removeAll()
        traceFinger = nil
        traceFinished = false
        traceIgnored = nil
    }

    /// Follows the first finger that touches down after tracing began, until it lifts.
    mutating func trace(_ contacts: [TrackpadHitDetector.Contact]) {
        guard !traceFinished else { return }
        let ignored = traceIgnored ?? Set(contacts.map(\.id))
        traceIgnored = ignored
        if traceFinger == nil { traceFinger = contacts.first { !ignored.contains($0.id) }?.id }
        guard let finger = traceFinger else { return }
        guard let contact = contacts.first(where: { $0.id == finger }) else {
            traceFinished = true
            return
        }
        let point = ZonePoint(x: contact.x, y: contact.y)
        if let last = trace.last, hypot(point.x - last.x, point.y - last.y) < 0.003 { return }
        trace.append(point)
    }
}

private let shared = OSAllocatedUnfairLock(initialState: SharedState())

// MTTouch layout (96 bytes): identifier at 16, state at 20,
// normalized position x, y (Float) at 32 and 36, contact size (Float) at 48.
private let touchStride = 96
/// Contact states, as recorded on a real trackpad: a touch goes 1 → 3 → 4
/// when firm, 1 → 2 when feather-light (it never reaches 4), and 5…7 while
/// lifting. Drums hear every contact (1…4); the spinner only firm ones.
private let contactStates: ClosedRange<Int32> = 1...4
private let firmStates: ClosedRange<Int32> = 3...4

/// Runs on the framework's own thread, about 100 times a second per device.
private func contactFrame(
    _ device: UnsafeMutableRawPointer?,
    _ touches: UnsafeRawPointer?,
    _ count: Int32,
    _ timestamp: Double,
    _ frame: Int32
) -> Int32 {
    var contacts: [TrackpadHitDetector.Contact] = []
    var firm: [TrackpadDrive.Contact] = []
    if let touches {
        for index in 0..<Int(count) {
            let touch = touches + index * touchStride
            let state = touch.load(fromByteOffset: 20, as: Int32.self)
            guard contactStates.contains(state) else { continue }
            if firmStates.contains(state) {
                firm.append(TrackpadDrive.Contact(
                    id: touch.load(fromByteOffset: 16, as: Int32.self),
                    x: Double(touch.load(fromByteOffset: 32, as: Float.self)),
                    y: Double(touch.load(fromByteOffset: 36, as: Float.self))
                ))
            }
            contacts.append(TrackpadHitDetector.Contact(
                id: touch.load(fromByteOffset: 16, as: Int32.self),
                x: Double(touch.load(fromByteOffset: 32, as: Float.self)),
                y: Double(touch.load(fromByteOffset: 36, as: Float.self)),
                size: Double(touch.load(fromByteOffset: 48, as: Float.self))
            ))
        }
    }
    let now = ProcessInfo.processInfo.systemUptime
    let frameContacts = contacts
    let firmContacts = firm
    let (shouldWake, hits) = shared.withLock { state -> (Bool, [TrackpadHitDetector.Hit]) in
        state.lastFrame = now
        switch state.mode {
        case .spinner:
            state.drive.update(contacts: firmContacts, timestamp: timestamp)
            guard state.drive.target != nil, !state.wakePending else { return (false, []) }
            state.wakePending = true
            return (true, [])
        case .drums(let reportsTaps):
            state.touching = frameContacts
            let hits = state.hits.update(contacts: frameContacts)
            return (false, reportsTaps ? hits : [])
        case .tracing:
            state.trace(frameContacts)
            return (false, [])
        }
    }
    if shouldWake {
        DispatchQueue.main.async {
            MainActor.assumeIsolated { MultitouchTrackpad.handleActivity() }
        }
    }
    if !hits.isEmpty {
        // Straight to the main thread: a drum hit can't wait.
        DispatchQueue.main.async {
            MainActor.assumeIsolated { MultitouchTrackpad.handleHits(hits) }
        }
    }
    return 0
}
