import Foundation

/// Identifies a keyboard sound pack: built-in, or imported into the library.
public enum KeyPackID: Hashable, Sendable, Codable {
    case builtin(KeyClickSynth.Profile)
    /// The folder name inside the app's pack library.
    case imported(String)

    public static let `default` = KeyPackID.builtin(.clicky)

    // Stored as a plain string ("builtin:clicky", "imported:<folder>") so the
    // JSON stays readable and unknown values degrade to the default.
    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = KeyPackID(rawValue: raw) ?? .default
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public init?(rawValue: String) {
        let parts = rawValue.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return nil }
        switch parts[0] {
        case "builtin":
            guard let profile = KeyClickSynth.Profile(rawValue: parts[1]) else { return nil }
            self = .builtin(profile)
        case "imported":
            self = .imported(parts[1])
        default:
            return nil
        }
    }

    public var rawValue: String {
        switch self {
        case .builtin(let profile): "builtin:\(profile.rawValue)"
        case .imported(let folder): "imported:\(folder)"
        }
    }
}

public struct KeyboardSoundSettings: Codable, Equatable, Sendable {
    public var pack: KeyPackID
    public var volume: Float
    public var playsReleaseSounds: Bool

    public init(pack: KeyPackID = .default, volume: Float = 0.8, playsReleaseSounds: Bool = true) {
        self.pack = pack
        self.volume = volume
        self.playsReleaseSounds = playsReleaseSounds
    }

    private enum CodingKeys: String, CodingKey { case pack, volume, playsReleaseSounds }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        pack = try container.decodeIfPresent(KeyPackID.self, forKey: .pack) ?? .default
        volume = (try container.decodeIfPresent(Float.self, forKey: .volume) ?? 0.8).clamped(to: Volume.module)
        playsReleaseSounds = try container.decodeIfPresent(Bool.self, forKey: .playsReleaseSounds) ?? true
    }
}
