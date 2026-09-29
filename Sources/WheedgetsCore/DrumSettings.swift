import Carbon.HIToolbox
import Foundation

/// What a pad plays: a synthesized drum or a sample file the user imported.
public enum SoundSource: Codable, Hashable, Sendable {
    case builtin(DrumSound)
    /// `fileName` is the copy inside the app's sample library; `displayName` is
    /// the original file name without its extension.
    case sample(fileName: String, displayName: String)
}

/// One key bound to one sound.
public struct Pad: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    /// Virtual key code (a physical key position), so bindings do not depend on
    /// the active keyboard layout: J stays J with a Russian layout active.
    public var keyCode: UInt16
    public var source: SoundSource
    /// Per-pad volume, 0…1.
    public var gain: Float

    public init(id: UUID = UUID(), keyCode: UInt16, source: SoundSource, gain: Float = 1) {
        self.id = id
        self.keyCode = keyCode
        self.source = source
        self.gain = gain
    }

    /// Home-row friendly layout: kick on F and Space, snare on J, hats under the
    /// right hand, toms on the row above, cymbals on the edges.
    public static func makeDefaultKit() -> [Pad] {
        let layout: [(Int, DrumSound)] = [
            (kVK_ANSI_A, .crash), (kVK_ANSI_U, .tomHigh), (kVK_ANSI_I, .tomMid), (kVK_ANSI_O, .tomLow),
            (kVK_ANSI_Semicolon, .ride), (kVK_ANSI_K, .closedHat), (kVK_ANSI_L, .openHat), (kVK_ANSI_D, .clap),
            (kVK_ANSI_S, .rim), (kVK_ANSI_J, .snare), (kVK_ANSI_F, .kick), (kVK_Space, .kick)
        ]
        return layout.map { Pad(keyCode: UInt16($0.0), source: .builtin($0.1)) }
    }
}

public struct DrumSettings: Codable, Equatable, Sendable {
    public var pads: [Pad]
    public var control: DrumControl
    public var trackpad: DrumTrackpadSettings
    public var volume: Float
    public var keyHandling: KeyHandling
    /// Show the floating pad panel while the drums are on.
    public var showsPanel: Bool

    public init(
        pads: [Pad] = Pad.makeDefaultKit(),
        control: DrumControl = .keyboard,
        trackpad: DrumTrackpadSettings = .init(),
        volume: Float = 1,
        keyHandling: KeyHandling = .capture,
        showsPanel: Bool = true
    ) {
        self.pads = pads
        self.control = control
        self.trackpad = trackpad
        self.volume = volume
        self.keyHandling = keyHandling
        self.showsPanel = showsPanel
    }

    private enum CodingKeys: String, CodingKey {
        case pads, control, trackpad, volume, keyHandling, showsPanel
        case panelVisible // written by older versions
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        pads = try container.decodeIfPresent([Pad].self, forKey: .pads) ?? Pad.makeDefaultKit()
        control = (try? container.decodeIfPresent(DrumControl.self, forKey: .control)) ?? .keyboard
        trackpad = (try? container.decodeIfPresent(DrumTrackpadSettings.self, forKey: .trackpad)) ?? .init()
        volume = (try container.decodeIfPresent(Float.self, forKey: .volume) ?? 1).clamped(to: Volume.module)
        keyHandling = (try? container.decodeIfPresent(KeyHandling.self, forKey: .keyHandling)) ?? .capture
        showsPanel = try container.decodeIfPresent(Bool.self, forKey: .showsPanel)
            ?? container.decodeIfPresent(Bool.self, forKey: .panelVisible)
            ?? true
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(pads, forKey: .pads)
        try container.encode(control, forKey: .control)
        try container.encode(trackpad, forKey: .trackpad)
        try container.encode(volume, forKey: .volume)
        try container.encode(keyHandling, forKey: .keyHandling)
        try container.encode(showsPanel, forKey: .showsPanel)
    }

    /// Lookup table used on every key press while play mode is on.
    public var padsByKey: [UInt16: Pad] {
        Dictionary(pads.map { ($0.keyCode, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// Binds `keyCode` to the pad. A pad that already used that key takes over
    /// this pad's previous key, so two pads never share one key.
    public mutating func assignKey(_ keyCode: UInt16, toPad id: Pad.ID) {
        guard keyCode != KeyCodes.escape,
              let index = pads.firstIndex(where: { $0.id == id }) else { return }
        let previous = pads[index].keyCode
        if let other = pads.firstIndex(where: { $0.keyCode == keyCode && $0.id != id }) {
            pads[other].keyCode = previous
        }
        pads[index].keyCode = keyCode
    }

    /// Adds a pad on the first free letter or digit key. Returns nil when all are taken.
    @discardableResult
    public mutating func addPad(source: SoundSource = .builtin(.snare)) -> Pad? {
        let used = Set(pads.map(\.keyCode))
        guard let key = KeyCodes.bindingCandidates.first(where: { !used.contains($0) }) else { return nil }
        let pad = Pad(keyCode: key, source: source)
        pads.append(pad)
        return pad
    }

    /// Imported samples in use, by pads or trackpad zones.
    public var referencedSampleFiles: Set<String> {
        Set((pads.map(\.source) + trackpad.zones + trackpad.customZones.map(\.sound)).compactMap {
            if case .sample(let fileName, _) = $0 { fileName } else { nil }
        })
    }
}
