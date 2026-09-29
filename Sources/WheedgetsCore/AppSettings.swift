import Foundation

/// Everything the app persists, one slice per module. Every field decodes
/// leniently, so settings saved by an older version survive new fields.
public struct AppSettings: Codable, Equatable, Sendable {
    public var masterVolume: Float
    public var widgets: WidgetHostSettings
    public var drums: DrumSettings
    public var spinner: SpinnerSettings
    public var keyboardSounds: KeyboardSoundSettings

    public init(
        masterVolume: Float = 1,
        widgets: WidgetHostSettings = .init(),
        drums: DrumSettings = .init(),
        spinner: SpinnerSettings = .init(),
        keyboardSounds: KeyboardSoundSettings = .init()
    ) {
        self.masterVolume = masterVolume
        self.widgets = widgets
        self.drums = drums
        self.spinner = spinner
        self.keyboardSounds = keyboardSounds
    }

    // "playMode" is the key older versions wrote for the widget host.
    private enum CodingKeys: String, CodingKey {
        case masterVolume, widgets = "playMode", drums, spinner, keyboardSounds
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        masterVolume = (try container.decodeIfPresent(Float.self, forKey: .masterVolume) ?? 1).clamped(to: Volume.master)
        widgets = try container.decodeIfPresent(WidgetHostSettings.self, forKey: .widgets) ?? .init()
        drums = try container.decodeIfPresent(DrumSettings.self, forKey: .drums) ?? .init()
        spinner = try container.decodeIfPresent(SpinnerSettings.self, forKey: .spinner) ?? .init()
        keyboardSounds = try container.decodeIfPresent(KeyboardSoundSettings.self, forKey: .keyboardSounds) ?? .init()
    }
}

public enum Volume {
    /// The app's overall level, up to the system volume.
    public static let master: ClosedRange<Float> = 0...1
    /// A module's level. Above 1 the module's limiter adds gain without clipping.
    public static let module: ClosedRange<Float> = 0...2
}

/// The fidget widgets. Exactly one is selected; the shortcut turns it on and off.
public enum WidgetKind: String, Codable, CaseIterable, Sendable, Identifiable {
    case drums
    case spinner
    case keyboardSounds

    public var id: Self { self }
}

/// What happens to a widget's keys while it is on.
public enum KeyHandling: String, Codable, CaseIterable, Sendable {
    /// The widget consumes its keys; the frontmost app never sees them.
    case capture
    /// The widget reacts and every key still types as usual.
    case passThrough
}

public struct WidgetHostSettings: Codable, Equatable, Sendable {
    public var hotkey: Hotkey
    public var selected: WidgetKind

    public init(hotkey: Hotkey = .toggleDefault, selected: WidgetKind = .drums) {
        self.hotkey = hotkey
        self.selected = selected
    }

    // "instrument" is the key older versions wrote.
    private enum CodingKeys: String, CodingKey { case hotkey, selected, instrument }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hotkey = try container.decodeIfPresent(Hotkey.self, forKey: .hotkey) ?? .toggleDefault
        selected = (try? container.decodeIfPresent(WidgetKind.self, forKey: .selected))
            ?? (try? container.decodeIfPresent(WidgetKind.self, forKey: .instrument))
            ?? .drums
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(hotkey, forKey: .hotkey)
        try container.encode(selected, forKey: .selected)
    }
}
