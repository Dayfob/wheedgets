import Foundation

/// Turns finger movement on the trackpad into the speed a finger would drag
/// a spinner toward, as if the trackpad were the spinner's face.
///
/// What counts is motion *around* the trackpad's center: sweeping up to the
/// right of center turns it counterclockwise, up to the left clockwise.
/// Speeds are scaled by `calibration`, so that at a speed ratio of 1 the
/// spinner feels like it moves with the finger.
///
/// Two kinds of gesture, told apart by how long the finger has been down:
/// - a *flick* (the first moments of a touch) pushes: its speed adds to the
///   spin, so a flick along the spin speeds it up and never slows it;
/// - a *drag* (a finger that stays down and keeps moving) holds the spinner,
///   which then turns exactly at the finger's speed.
/// Positions are the trackpad's normalized 0…1 coordinates, y pointing up.
public struct TrackpadDrive: Sendable {
    public struct Contact: Sendable {
        public var id: Int32
        public var x: Double
        public var y: Double

        public init(id: Int32, x: Double, y: Double) {
            self.id = id
            self.x = x
            self.y = y
        }
    }

    /// What feels one-to-one. The finger's raw angle around the pad's center
    /// undersells a gesture (fingers rarely circle the exact center, and the
    /// motion is smoothed), so the spinner felt three times too slow. Tuned by feel.
    public static let calibration = 3.0

    /// How long a touch counts as a flick before it becomes a drag.
    public static let flickWindow = 0.3
    /// How long after touching down the drive decides "grab" or "gesture".
    public static let grabWindow = 0.06
    /// Moving less than this (normalized pad units, about 1 mm) by then is a grab.
    static let grabThreshold = 0.012
    /// A finger resting this long starts holding the spinner back…
    public static let holdDelay = 0.2
    /// …and grips fully after this much longer.
    public static let holdRamp = 0.5
    /// Slower fingers are resting or drifting, not sweeping.
    static let minimumFingerSpeed = 0.25
    /// Trackpads are wider than tall; correct so a circle is a circle.
    static let aspect = 1.5

    /// The user's speed ratio on top of `calibration`; 1 feels one-to-one.
    public var sensitivity = 1.0

    /// The spinner speed the sweeping fingers drag toward, in rev/s
    /// (positive = clockwise), or nil when no finger is sweeping.
    public private(set) var target: Double?

    /// The fingers came down moments ago: the gesture is a flick, not a drag.
    public private(set) var isFlicking = false

    private var touchStart: Double?
    private var stillSince: Double?
    private var touchOrigins: [Int32: (x: Double, y: Double)] = [:]
    private var grabDecided = false

    /// The fingers came down and stayed put: they grab the spinner, like a
    /// finger laid on a real one. Ends as soon as they start moving.
    public private(set) var isGrabbing = false

    /// How long the fingers have rested on the pad without moving (0 while
    /// moving or lifted).
    public private(set) var stillDuration = 0.0

    /// 0…1: how firmly resting fingers hold the spinner. Zero at first, so
    /// the brief pause at the start of every gesture doesn't brake.
    public var holdStrength: Double {
        ((stillDuration - Self.holdDelay) / Self.holdRamp).clamped(to: 0...1)
    }

    private var fingers: [Int32: (x: Double, y: Double, time: Double, vx: Double, vy: Double)] = [:]

    public init() {}

    public mutating func update(contacts: [Contact], timestamp: Double) {
        var next: [Int32: (x: Double, y: Double, time: Double, vx: Double, vy: Double)] = [:]
        var spins: [Double] = []

        for contact in contacts {
            let x = contact.x * Self.aspect, y = contact.y
            var vx = 0.0, vy = 0.0
            if let previous = fingers[contact.id], timestamp > previous.time {
                let dt = timestamp - previous.time
                // Smooth the per-frame velocity; single frames are noisy.
                vx = previous.vx * 0.5 + (x - previous.x) / dt * 0.5
                vy = previous.vy * 0.5 + (y - previous.y) / dt * 0.5
            }
            next[contact.id] = (x, y, timestamp, vx, vy)

            guard hypot(vx, vy) >= Self.minimumFingerSpeed else { continue }
            let rx = x - 0.5 * Self.aspect, ry = y - 0.5
            // Angular velocity around the center, rad/s, counterclockwise positive.
            // The floor keeps sweeps right through the middle from exploding.
            let angular = (rx * vy - ry * vx) / max(rx * rx + ry * ry, 0.04)
            spins.append(angular)
        }

        fingers = next
        if contacts.isEmpty {
            touchStart = nil
        } else if touchStart == nil {
            touchStart = timestamp
        }
        isFlicking = touchStart.map { timestamp - $0 < Self.flickWindow } ?? false
        updateGrab(contacts: contacts, timestamp: timestamp, moving: !spins.isEmpty)
        if contacts.isEmpty || !spins.isEmpty {
            stillSince = nil
        } else if stillSince == nil {
            stillSince = timestamp
        }
        stillDuration = stillSince.map { timestamp - $0 } ?? 0
        guard !spins.isEmpty else {
            target = nil
            return
        }
        let turnsPerSecond = spins.reduce(0, +) / Double(spins.count) / (2 * .pi)

        // Counterclockwise on the pad is counterclockwise for the spinner,
        // whose positive direction is clockwise.
        target = (-turnsPerSecond * Self.calibration * sensitivity).clamped(to: -SpinnerPhysics.maxSpeed...SpinnerPhysics.maxSpeed)
    }

    private mutating func updateGrab(contacts: [Contact], timestamp: Double, moving: Bool) {
        guard let touchStart else {
            touchOrigins.removeAll()
            grabDecided = false
            isGrabbing = false
            return
        }
        for contact in contacts where touchOrigins[contact.id] == nil {
            touchOrigins[contact.id] = (contact.x, contact.y)
        }
        if !grabDecided && timestamp - touchStart >= Self.grabWindow {
            grabDecided = true
            let travel = contacts.map { contact -> Double in
                guard let origin = touchOrigins[contact.id] else { return 0 }
                return hypot(contact.x - origin.x, contact.y - origin.y)
            }.max() ?? 0
            isGrabbing = travel < Self.grabThreshold
        }
        if moving { isGrabbing = false }
    }

    /// All fingers lifted.
    public mutating func reset() {
        fingers.removeAll()
        target = nil
        isFlicking = false
        touchStart = nil
        stillSince = nil
        stillDuration = 0
        touchOrigins.removeAll()
        grabDecided = false
        isGrabbing = false
    }
}
