import Carbon.HIToolbox
import Foundation

public enum SpinnerAction: String, Codable, CaseIterable, Sendable {
    /// Flick in the direction it already turns (clockwise from rest). Hold to keep pushing.
    case spin
    case spinClockwise
    case spinCounterClockwise
    /// Slows it down; keeps braking while held.
    case brake
    /// Brings it to a quick, smooth stop.
    case stop
}

public struct SpinnerBinding: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var keyCode: UInt16
    public var action: SpinnerAction

    public init(id: UUID = UUID(), keyCode: UInt16, action: SpinnerAction) {
        self.id = id
        self.keyCode = keyCode
        self.action = action
    }

    public static func makeDefaults() -> [SpinnerBinding] {
        [
            SpinnerBinding(keyCode: UInt16(kVK_Space), action: .spin),
            SpinnerBinding(keyCode: UInt16(kVK_RightArrow), action: .spinClockwise),
            SpinnerBinding(keyCode: UInt16(kVK_LeftArrow), action: .spinCounterClockwise),
            SpinnerBinding(keyCode: UInt16(kVK_DownArrow), action: .brake),
            SpinnerBinding(keyCode: UInt16(kVK_Return), action: .stop)
        ]
    }
}

/// How the spinner is driven. Only one at a time.
public enum SpinnerControl: String, Codable, CaseIterable, Sendable {
    case keyboard
    /// Finger movement on the trackpad, observed without blocking anything.
    case trackpad
}

/// Finishes after recent iPhone colors (17 Pro, Air, 17, 16).
public enum SpinnerColor: String, Codable, CaseIterable, Sendable {
    case cosmicOrange, deepBlue, silver, spaceBlack
    case skyBlue, lightGold, lavender, mistBlue
    case sage, pink, ultramarine, teal
}

public enum SpinnerVisibility: String, Codable, CaseIterable, Sendable {
    /// Shown while play mode runs with the spinner; it coasts to a stop, then fades.
    case whilePlaying
    /// Always on screen, like a toy on the desk.
    case always
}

public struct SpinnerSettings: Codable, Equatable, Sendable {
    public static let sizeRange: ClosedRange<Double> = 80...260
    public static let spinTimeRange: ClosedRange<Double> = 0.25...3
    /// Range for both push and brake strength.
    public static let strengthRange: ClosedRange<Double> = 0.25...3
    public static let defaultTypingBrakeKeys: [UInt16] = [UInt16(kVK_Delete)]

    public var control: SpinnerControl
    /// Trackpad speed ratio; 1 feels one-to-one.
    public var trackpadSensitivity: Double
    /// A finger resting on the trackpad slows the spinner.
    public var touchBrakes: Bool
    public var touchBrakeStrength: Double
    /// A finger that lands and stays put stops the spinner at once.
    public var touchStopsInstantly: Bool
    public var bindings: [SpinnerBinding]
    /// Every key press nudges the spinner, on top of the bindings.
    public var spinsOnAnyKey: Bool
    /// With `spinsOnAnyKey`, these keys slow it down instead (Backspace by default).
    public var typingBrakeKeys: [UInt16]
    /// Scales every push: flicks, typing nudges and holding.
    public var pushStrength: Double
    /// Scales every brake: brake keys, typing brake keys and holding them.
    public var brakeStrength: Double
    /// Holding a spin key keeps pushing, holding a brake key keeps braking.
    public var holdKeepsGoing: Bool
    public var keyHandling: KeyHandling
    public var visibility: SpinnerVisibility
    public var color: SpinnerColor
    public var size: Double
    /// Multiplies how long a spin lasts (bearing quality).
    public var spinTime: Double
    public var volume: Float

    public init(
        control: SpinnerControl = .keyboard,
        trackpadSensitivity: Double = 1,
        touchBrakes: Bool = true,
        touchBrakeStrength: Double = 1,
        touchStopsInstantly: Bool = false,
        bindings: [SpinnerBinding] = SpinnerBinding.makeDefaults(),
        spinsOnAnyKey: Bool = false,
        typingBrakeKeys: [UInt16] = SpinnerSettings.defaultTypingBrakeKeys,
        pushStrength: Double = 1,
        brakeStrength: Double = 1,
        holdKeepsGoing: Bool = true,
        keyHandling: KeyHandling = .capture,
        visibility: SpinnerVisibility = .whilePlaying,
        color: SpinnerColor = .cosmicOrange,
        size: Double = 150,
        spinTime: Double = 1,
        volume: Float = 0.8
    ) {
        self.control = control
        self.trackpadSensitivity = trackpadSensitivity
        self.touchBrakes = touchBrakes
        self.touchBrakeStrength = touchBrakeStrength
        self.touchStopsInstantly = touchStopsInstantly
        self.bindings = bindings
        self.spinsOnAnyKey = spinsOnAnyKey
        self.typingBrakeKeys = typingBrakeKeys
        self.pushStrength = pushStrength
        self.brakeStrength = brakeStrength
        self.holdKeepsGoing = holdKeepsGoing
        self.keyHandling = keyHandling
        self.visibility = visibility
        self.color = color
        self.size = size
        self.spinTime = spinTime
        self.volume = volume
    }

    private enum CodingKeys: String, CodingKey {
        // "trackpadSpeedRatio": the first version stored an uncalibrated value
        // under another key; dropping it resets the ratio to the new ×1.
        case control, trackpadSensitivity = "trackpadSpeedRatio", touchBrakes, touchBrakeStrength, touchStopsInstantly
        case bindings, spinsOnAnyKey, typingBrakeKeys, pushStrength, brakeStrength, holdKeepsGoing
        case keyHandling, visibility, color, size, spinTime, volume
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = SpinnerSettings()
        control = (try? c.decodeIfPresent(SpinnerControl.self, forKey: .control)) ?? defaults.control
        trackpadSensitivity = (try c.decodeIfPresent(Double.self, forKey: .trackpadSensitivity) ?? defaults.trackpadSensitivity)
            .clamped(to: Self.strengthRange)
        touchBrakes = try c.decodeIfPresent(Bool.self, forKey: .touchBrakes) ?? defaults.touchBrakes
        touchBrakeStrength = (try c.decodeIfPresent(Double.self, forKey: .touchBrakeStrength) ?? defaults.touchBrakeStrength)
            .clamped(to: Self.strengthRange)
        touchStopsInstantly = try c.decodeIfPresent(Bool.self, forKey: .touchStopsInstantly) ?? defaults.touchStopsInstantly
        bindings = (try? c.decodeIfPresent([SpinnerBinding].self, forKey: .bindings)) ?? defaults.bindings
        spinsOnAnyKey = try c.decodeIfPresent(Bool.self, forKey: .spinsOnAnyKey) ?? defaults.spinsOnAnyKey
        typingBrakeKeys = try c.decodeIfPresent([UInt16].self, forKey: .typingBrakeKeys) ?? defaults.typingBrakeKeys
        pushStrength = (try c.decodeIfPresent(Double.self, forKey: .pushStrength) ?? defaults.pushStrength)
            .clamped(to: Self.strengthRange)
        brakeStrength = (try c.decodeIfPresent(Double.self, forKey: .brakeStrength) ?? defaults.brakeStrength)
            .clamped(to: Self.strengthRange)
        holdKeepsGoing = try c.decodeIfPresent(Bool.self, forKey: .holdKeepsGoing) ?? defaults.holdKeepsGoing
        keyHandling = (try? c.decodeIfPresent(KeyHandling.self, forKey: .keyHandling)) ?? defaults.keyHandling
        visibility = (try? c.decodeIfPresent(SpinnerVisibility.self, forKey: .visibility)) ?? defaults.visibility
        color = (try? c.decodeIfPresent(SpinnerColor.self, forKey: .color)) ?? defaults.color
        size = (try c.decodeIfPresent(Double.self, forKey: .size) ?? defaults.size).clamped(to: Self.sizeRange)
        spinTime = (try c.decodeIfPresent(Double.self, forKey: .spinTime) ?? defaults.spinTime).clamped(to: Self.spinTimeRange)
        volume = (try c.decodeIfPresent(Float.self, forKey: .volume) ?? defaults.volume).clamped(to: Volume.module)
    }

    public var bindingsByKey: [UInt16: SpinnerBinding] {
        Dictionary(bindings.map { ($0.keyCode, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// Same swap rule as drum pads: two bindings never share a key.
    public mutating func assignKey(_ keyCode: UInt16, toBinding id: SpinnerBinding.ID) {
        guard keyCode != KeyCodes.escape,
              let index = bindings.firstIndex(where: { $0.id == id }) else { return }
        let previous = bindings[index].keyCode
        if let other = bindings.firstIndex(where: { $0.keyCode == keyCode && $0.id != id }) {
            bindings[other].keyCode = previous
        }
        bindings[index].keyCode = keyCode
    }

    public mutating func addTypingBrakeKey(_ keyCode: UInt16) {
        guard keyCode != KeyCodes.escape, !typingBrakeKeys.contains(keyCode) else { return }
        typingBrakeKeys.append(keyCode)
    }

    /// What a key does to the spinner. Bindings win; in typing mode the
    /// brake keys slow it and every other key nudges it.
    public func role(of keyCode: UInt16) -> KeyRole {
        if let binding = bindingsByKey[keyCode] { return .action(binding.action) }
        guard spinsOnAnyKey else { return .none }
        return typingBrakeKeys.contains(keyCode) ? .typingBrake : .typingNudge
    }

    public enum KeyRole: Equatable, Sendable {
        case none
        case action(SpinnerAction)
        case typingNudge
        case typingBrake
    }

    @discardableResult
    public mutating func addBinding(action: SpinnerAction = .spin) -> SpinnerBinding? {
        let used = Set(bindings.map(\.keyCode))
        guard let key = KeyCodes.bindingCandidates.first(where: { !used.contains($0) }) else { return nil }
        let binding = SpinnerBinding(keyCode: key, action: action)
        bindings.append(binding)
        return binding
    }
}
