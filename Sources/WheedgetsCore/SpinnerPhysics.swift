import Foundation

/// A fidget spinner on a ball bearing.
///
/// Velocity is in revolutions per second; positive is clockwise. Friction has
/// a viscous part (proportional to speed, dominant when fast) and a constant
/// part (bearing drag, which is what finally stops it), like a real spinner
/// that whirs for a long time and then settles quickly.
public struct SpinnerPhysics: Sendable, Equatable {
    public static let maxSpeed = 60.0
    /// One flick.
    public static let flick = 2.5
    /// A typing nudge when every key spins.
    public static let nudge = 0.6
    /// Push while a spin key is held, rev/s². Braking while held uses the
    /// same rate, so at equal strengths pushing and braking feel symmetric.
    public static let holdPush = 7.0

    public private(set) var angle = 0.0
    public private(set) var velocity = 0.0

    /// -1, 0 or 1: a spin key is held in that direction.
    public var pushDirection = 0
    public var isBraking = false
    public private(set) var isStopping = false

    /// 1 = normal. Larger values spin longer.
    public var spinTime = 1.0
    /// 1 = normal. Scales pushing while a spin key is held.
    public var pushStrength = 1.0
    /// 1 = normal. Scales braking while a brake key is held.
    public var brakeStrength = 1.0

    /// Speed a moving finger on the trackpad carries the spinner toward, if any.
    public private(set) var fingerTarget: Double?
    /// The spin when the current gesture began; flicks add to it.
    private var fingerBase: Double?

    /// 0…1: a finger resting on the trackpad holds the spinner back, like a
    /// finger laid on a real one.
    public var touchHold = 0.0
    /// Scales `touchHold`.
    public var touchBrakeStrength = 1.0
    /// At full hold and strength, the speed falls by e every 1/6 s.
    public static let touchGrip = 6.0
    /// A finger grabbing the spinner stops it almost at once.
    public var isGrabbed = false
    /// How firmly a finger grips the rim, 1/s: higher follows the finger sooner.
    public static let fingerGrip = 12.0

    public init() {}

    public var isResting: Bool {
        velocity == 0 && pushDirection == 0 && fingerTarget == nil
    }

    /// The direction a plain "spin" continues in.
    public var currentDirection: Int {
        velocity < 0 ? -1 : 1
    }

    public mutating func flick(direction: Int, strength: Double = flick) {
        isStopping = false
        velocity = (velocity + Double(direction) * strength).clamped(to: -Self.maxSpeed...Self.maxSpeed)
    }

    /// Takes `amount` rev/s off the speed, never reversing it.
    public mutating func slow(by amount: Double) {
        let slowed = max(0, abs(velocity) - amount)
        velocity = velocity < 0 ? -slowed : slowed
    }

    /// Feeds the trackpad: `speed` is the gesture's own speed (nil when no
    /// finger moves).
    /// - A flick along the spin pushes: its speed adds to the spin the
    ///   gesture started from, so it only ever speeds up.
    /// - A flick against the spin throws it the other way: it drops through
    ///   zero and picks up the flick's speed in the new direction.
    /// - A drag holds it: the speed follows the finger outright.
    public mutating func setFinger(speed: Double?, flicking: Bool) {
        guard let speed else {
            fingerTarget = nil
            fingerBase = nil
            return
        }
        let base = fingerBase ?? velocity
        fingerBase = base
        let against = base != 0 && speed != 0 && (speed > 0) != (base > 0)
        let target = flicking && !against ? base + speed : speed
        fingerTarget = target.clamped(to: -Self.maxSpeed...Self.maxSpeed)
    }

    public mutating func stop() {
        isStopping = true
        pushDirection = 0
    }

    public mutating func step(_ dt: Double) {
        guard dt > 0 else { return }
        let dt = min(dt, 0.1)

        if pushDirection != 0 {
            isStopping = false
            velocity += Double(pushDirection) * Self.holdPush * pushStrength * dt
        }

        if let target = fingerTarget {
            // A finger grips the rim and carries it at its own speed. The grip
            // takes a moment, so a swipe against the spin slows it through
            // zero, then turns it the other way, never flipping instantly.
            isStopping = false
            velocity += (target - velocity) * (1 - exp(-Self.fingerGrip * dt))
        }

        if isGrabbed && fingerTarget == nil {
            // Stopped within about a tenth of a second: reads as instant,
            // without a visible jump.
            velocity *= exp(-dt / 0.03)
            if abs(velocity) < 0.05 { velocity = 0 }
        } else if touchHold > 0 && fingerTarget == nil {
            velocity *= exp(-Self.touchGrip * touchBrakeStrength * touchHold * dt)
            if abs(velocity) < 0.05 { velocity = 0 }
        }

        if isStopping {
            // Exponential approach to zero: quick but without a jolt.
            velocity *= exp(-dt / 0.12)
            if abs(velocity) < 0.05 {
                velocity = 0
                isStopping = false
            }
        } else if pushDirection == 0 {
            let viscous = 0.045 / spinTime
            let bearing = 0.12 / spinTime + (isBraking ? Self.holdPush * brakeStrength : 0)
            let slowed = abs(velocity) * exp(-viscous * dt) - bearing * dt
            velocity = slowed <= 0 ? 0 : slowed * (velocity < 0 ? -1 : 1)
        }

        velocity = velocity.clamped(to: -Self.maxSpeed...Self.maxSpeed)
        angle = (angle + velocity * dt).truncatingRemainder(dividingBy: 1)
    }
}
