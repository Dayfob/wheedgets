import WheedgetsCore
import SwiftUI

extension DrumSound {
    var displayName: String {
        switch self {
        case .kick: String(localized: "Kick")
        case .snare: String(localized: "Snare")
        case .rim: String(localized: "Rimshot")
        case .clap: String(localized: "Clap")
        case .closedHat: String(localized: "Closed Hi-Hat")
        case .openHat: String(localized: "Open Hi-Hat")
        case .tomHigh: String(localized: "High Tom")
        case .tomMid: String(localized: "Mid Tom")
        case .tomLow: String(localized: "Low Tom")
        case .crash: String(localized: "Crash")
        case .ride: String(localized: "Ride")
        case .cowbell: String(localized: "Cowbell")
        }
    }

    /// Pads are color-coded by family: drums warm, hats and cymbals cool.
    var tint: Color {
        switch self {
        case .kick: .red
        case .snare: .orange
        case .rim, .clap: .pink
        case .closedHat, .openHat: .cyan
        case .tomHigh, .tomMid, .tomLow: .purple
        case .crash, .ride: .blue
        case .cowbell: .green
        }
    }
}

extension SoundSource {
    var displayName: String {
        switch self {
        case .builtin(let sound): sound.displayName
        case .sample(_, let name): name
        }
    }

    var tint: Color {
        switch self {
        case .builtin(let sound): sound.tint
        case .sample: .indigo
        }
    }
}
