import Foundation

/// A keyboard sound pack: which clip plays when a key goes down or up.
///
/// Imported packs come from Mechvibes' `config.json`; built-in packs are
/// synthesized. Lookups use Mechvibes key codes (see `MechvibesKeyCodes`).
public struct KeySoundPack: Equatable, Sendable {
    public enum Phase: String, Hashable, Sendable {
        case press
        case release
    }

    public enum Clip: Hashable, Sendable {
        /// A slice of the pack's single sound file.
        case slice(startMs: Double, durationMs: Double)
        /// A file inside the pack folder, relative path.
        case file(String)
        /// A built-in synthesized sound.
        case synth(KeyClickSynth.Sound)
    }

    public var name: String
    /// The sound file that `.slice` clips cut from (Mechvibes "single" packs).
    public var spriteFile: String?
    public var press: [Int: [Clip]]
    public var release: [Int: [Clip]]
    /// Used for keys the pack does not define (Mechvibes v2 `sound` / `soundup`).
    public var fallbackPress: [Clip]
    public var fallbackRelease: [Clip]

    public init(
        name: String,
        spriteFile: String? = nil,
        press: [Int: [Clip]],
        release: [Int: [Clip]] = [:],
        fallbackPress: [Clip] = [],
        fallbackRelease: [Clip] = []
    ) {
        self.name = name
        self.spriteFile = spriteFile
        self.press = press
        self.release = release
        self.fallbackPress = fallbackPress
        self.fallbackRelease = fallbackRelease
    }

    /// Candidate clips for a key; play one at random. Keys the pack leaves out
    /// fall back to the pack's generic sound, then to the sound of "A", so
    /// every key clicks, not only the ones the pack author recorded.
    public func clips(for code: Int, phase: Phase) -> [Clip] {
        let defined = phase == .press ? press : release
        if let clips = defined[code], !clips.isEmpty { return clips }
        let fallback = phase == .press ? fallbackPress : fallbackRelease
        if !fallback.isEmpty { return fallback }
        return defined[MechvibesKeyCodes.generic] ?? []
    }

    /// Every clip the pack can play, for preloading.
    public var allClips: Set<Clip> {
        var clips = Set(fallbackPress + fallbackRelease)
        for list in press.values { clips.formUnion(list) }
        for list in release.values { clips.formUnion(list) }
        return clips
    }

    /// Drops clips that cannot be played (for example files a pack lists but
    /// does not contain), so those keys use the pack's fallbacks instead.
    public func removingClips(where isUnplayable: (Clip) -> Bool) -> KeySoundPack {
        func clean(_ map: [Int: [Clip]]) -> [Int: [Clip]] {
            map.compactMapValues { clips in
                let playable = clips.filter { !isUnplayable($0) }
                return playable.isEmpty ? nil : playable
            }
        }
        var pack = self
        pack.press = clean(press)
        pack.release = clean(release)
        pack.fallbackPress = fallbackPress.filter { !isUnplayable($0) }
        pack.fallbackRelease = fallbackRelease.filter { !isUnplayable($0) }
        return pack
    }

    /// Files the pack needs, relative to its folder.
    public var referencedFiles: Set<String> {
        var files = Set(allClips.compactMap { if case .file(let path) = $0 { path } else { nil } })
        if let spriteFile { files.insert(spriteFile) }
        return files
    }
}

// MARK: - Mechvibes

extension KeySoundPack {
    public enum ParseError: LocalizedError, Equatable {
        case notJSON
        case missingField(String)
        case unsupportedType(String)
        case unsafePath(String)
        case empty

        public var errorDescription: String? {
            switch self {
            case .notJSON: String(localized: "config.json is not valid JSON.")
            case .missingField(let field): String(localized: "config.json has no “\(field)” field.")
            case .unsupportedType(let type): String(localized: "Unsupported key_define_type “\(type)”.")
            case .unsafePath(let path): String(localized: "The pack refers to a file outside its folder: \(path)")
            case .empty: String(localized: "The pack defines no sounds.")
            }
        }
    }

    /// Parses a Mechvibes `config.json` (config versions 1 and 2).
    ///
    /// - `key_define_type: "single"`: `sound` is one file, each define is
    ///   `[start_ms, duration_ms]`.
    /// - `key_define_type: "multi"`: each define is a file path. Version 2 adds
    ///   `sound` / `soundup` as fallbacks for undefined keys, and `{0-4}` in a
    ///   path means "one of these numbered files" (picked per key press here).
    /// - A define named `"<code>-up"` is the key release sound.
    public static func parseMechvibes(_ data: Data) throws -> KeySoundPack {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ParseError.notJSON
        }
        guard let name = json["name"] as? String else { throw ParseError.missingField("name") }
        guard let type = json["key_define_type"] as? String else { throw ParseError.missingField("key_define_type") }
        guard let defines = json["defines"] as? [String: Any] else { throw ParseError.missingField("defines") }
        let version = (json["version"] as? Int) ?? 1
        let sound = json["sound"] as? String

        var press: [Int: [Clip]] = [:]
        var release: [Int: [Clip]] = [:]
        var pack = KeySoundPack(name: name, press: [:])

        func store(_ key: String, _ clips: [Clip]) {
            guard !clips.isEmpty else { return }
            if key.hasSuffix("-up"), let code = Int(key.dropLast(3)) {
                release[code] = clips
            } else if let code = Int(key) {
                press[code] = clips
            }
        }

        switch type {
        case "single":
            guard let sound else { throw ParseError.missingField("sound") }
            pack.spriteFile = try safePath(sound)
            for (key, value) in defines {
                guard let range = value as? [Any], range.count >= 2,
                      let start = (range[0] as? NSNumber)?.doubleValue,
                      let duration = (range[1] as? NSNumber)?.doubleValue,
                      duration > 0 else { continue }
                store(key, [.slice(startMs: start, durationMs: duration)])
            }
        case "multi":
            for (key, value) in defines {
                guard let path = value as? String else { continue }
                store(key, try expand(path).map(Clip.file))
            }
            if version >= 2 {
                pack.fallbackPress = try sound.map { try expand($0).map(Clip.file) } ?? []
                pack.fallbackRelease = try (json["soundup"] as? String).map { try expand($0).map(Clip.file) } ?? []
            }
        default:
            throw ParseError.unsupportedType(type)
        }

        pack.press = press
        pack.release = release
        guard !pack.allClips.isEmpty else { throw ParseError.empty }
        return pack
    }

    /// `press/GENERIC_R{0-4}.mp3` → `press/GENERIC_R0.mp3` … `press/GENERIC_R4.mp3`.
    static func expand(_ path: String) throws -> [String] {
        let safe = try safePath(path)
        guard let open = safe.firstIndex(of: "{"),
              let close = safe[open...].firstIndex(of: "}") else { return [safe] }
        let bounds = safe[safe.index(after: open)..<close].split(separator: "-").compactMap { Int($0) }
        guard bounds.count == 2, bounds[0] <= bounds[1], bounds[1] - bounds[0] < 100 else { return [safe] }
        return (bounds[0]...bounds[1]).map {
            safe.replacingCharacters(in: open...close, with: String($0))
        }
    }

    /// Pack files must stay inside the pack folder.
    static func safePath(_ path: String) throws -> String {
        let components = path.split(separator: "/")
        guard !path.hasPrefix("/"), !path.hasPrefix("~"), !components.contains("..") else {
            throw ParseError.unsafePath(path)
        }
        return path
    }
}
