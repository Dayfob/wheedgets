/// The built-in kit. Every sound is synthesized by `DrumSynth`, so the app ships
/// without sample files (and without sample licensing questions).
public enum DrumSound: String, CaseIterable, Codable, Sendable, Identifiable {
    case kick
    case snare
    case rim
    case clap
    case closedHat
    case openHat
    case tomHigh
    case tomMid
    case tomLow
    case crash
    case ride
    case cowbell

    public var id: Self { self }

    /// Peak level after normalization. Keeps the kit balanced out of the box:
    /// cymbals and hats sit under the kick and snare, like on a real kit.
    public var level: Float {
        switch self {
        case .kick: 0.95
        case .snare: 0.85
        case .rim: 0.6
        case .clap: 0.75
        case .closedHat, .openHat: 0.5
        case .tomHigh, .tomMid, .tomLow: 0.8
        case .crash: 0.55
        case .ride: 0.45
        case .cowbell: 0.55
        }
    }

    /// Stereo placement from the drummer's perspective, -1 (left) … 1 (right).
    public var pan: Float {
        switch self {
        case .closedHat, .openHat: -0.3
        case .tomHigh: -0.15
        case .tomMid: 0.05
        case .tomLow: 0.25
        case .crash: -0.4
        case .ride: 0.4
        default: 0
        }
    }
}
