import Carbon.HIToolbox
import CoreGraphics
import OSLog

/// A keyboard event tap. Use it through `KeyboardHub`, which decides when the
/// tap should exist and in which mode.
@MainActor
final class KeyInterceptor {
    enum Mode: Equatable {
        /// Observes keys without delaying them. Nothing can be swallowed.
        case listen
        /// Sits in the event path and may swallow keys. Requires Accessibility.
        case filter
    }

    /// Returns true to swallow the event (only honored in `.filter` mode).
    var handler: ((KeyEvent) -> Bool)?

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private(set) var mode: Mode?

    /// Returns false when macOS refuses the tap (no Accessibility access).
    func start(_ mode: Mode) -> Bool {
        if self.mode == mode { return true }
        stop()

        let types: [CGEventType] = [.keyDown, .keyUp, .flagsChanged]
        let mask = types.reduce(CGEventMask(0)) { $0 | CGEventMask(1 << $1.rawValue) }
        func create(_ options: CGEventTapOptions) -> CFMachPort? {
            CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: options,
                eventsOfInterest: mask,
                callback: keyTapCallback,
                userInfo: Unmanaged.passUnretained(self).toOpaque()
            )
        }
        // A listen-only tap never holds up typing, even if the main thread is
        // busy. Some systems grant it only with Input Monitoring, so fall back
        // to a filtering tap, which Accessibility access always allows.
        guard let tap = mode == .listen ? (create(.listenOnly) ?? create(.defaultTap)) : create(.defaultTap) else {
            Logger.input.error("CGEvent.tapCreate failed; Accessibility access is missing or stale")
            return false
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        runLoopSource = source
        self.mode = mode
        return true
    }

    func stop() {
        guard let tap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        CFMachPortInvalidate(tap)
        self.tap = nil
        runLoopSource = nil
        mode = nil
    }

    /// macOS disables a tap that is too slow or when secure input toggles; turn it back on.
    fileprivate func reenable() {
        guard let tap else { return }
        Logger.input.notice("Event tap was disabled by the system; re-enabling")
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    fileprivate func handle(_ event: KeyEvent) -> Bool {
        let swallow = handler?(event) ?? false
        return swallow && mode == .filter
    }
}

/// Runs on the main run loop, where the tap's source was added.
private func keyTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let interceptor = Unmanaged<KeyInterceptor>.fromOpaque(userInfo).takeUnretainedValue()
    let keyCode = UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))

    let keyEvent: KeyEvent
    switch type {
    case .tapDisabledByTimeout, .tapDisabledByUserInput:
        MainActor.assumeIsolated { interceptor.reenable() }
        return Unmanaged.passUnretained(event)
    case .keyDown, .keyUp:
        keyEvent = KeyEvent(
            keyCode: keyCode,
            flags: event.flags,
            isDown: type == .keyDown,
            isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0,
            isModifier: false
        )
    case .flagsChanged:
        guard let isDown = ModifierKeys.isDown(keyCode, flags: event.flags) else {
            return Unmanaged.passUnretained(event)
        }
        keyEvent = KeyEvent(keyCode: keyCode, flags: event.flags, isDown: isDown, isRepeat: false, isModifier: true)
    default:
        return Unmanaged.passUnretained(event)
    }
    let swallow = MainActor.assumeIsolated { interceptor.handle(keyEvent) }
    return swallow ? nil : Unmanaged.passUnretained(event)
}

/// A modifier key reports only "flags changed"; whether it went down or up is
/// read from the device-specific bit for that exact key, so left and right
/// Shift are tracked separately.
enum ModifierKeys {
    private static let deviceMasks: [Int: UInt64] = [
        kVK_Control: 0x0001,
        kVK_Shift: 0x0002,
        kVK_RightShift: 0x0004,
        kVK_Command: 0x0008,
        kVK_RightCommand: 0x0010,
        kVK_Option: 0x0020,
        kVK_RightOption: 0x0040,
        kVK_RightControl: 0x2000
    ]

    /// nil for keys that are not modifiers.
    static func isDown(_ keyCode: UInt16, flags: CGEventFlags) -> Bool? {
        switch Int(keyCode) {
        // Caps Lock and Fn report a single event per press, never a release.
        case kVK_CapsLock, kVK_Function:
            return true
        case let code:
            guard let mask = deviceMasks[code] else { return nil }
            return flags.rawValue & mask != 0
        }
    }
}
