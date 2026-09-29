import AVFoundation
import WheedgetsCore

/// A pack decoded into playable buffers in the engine's format.
/// Immutable after loading, so it is safe to hand across threads.
final class LoadedKeyPack: @unchecked Sendable {
    let id: KeyPackID
    let sampleRate: Double
    private let pack: KeySoundPack
    private let buffers: [KeySoundPack.Clip: AVAudioPCMBuffer]

    init(id: KeyPackID, sampleRate: Double, pack: KeySoundPack, buffers: [KeySoundPack.Clip: AVAudioPCMBuffer]) {
        self.id = id
        self.sampleRate = sampleRate
        self.pack = pack
        self.buffers = buffers
    }

    /// One of the key's candidate sounds, picked at random.
    func buffer(for code: Int, phase: KeySoundPack.Phase) -> AVAudioPCMBuffer? {
        pack.clips(for: code, phase: phase).randomElement().flatMap { buffers[$0] }
    }
}

/// Decodes packs off the main thread: a sprite pack is one long file (often
/// close to a minute of audio) cut into a hundred slices.
enum KeyPackLoader {
    enum LoadError: LocalizedError {
        case undecodable(String)
        case silent

        var errorDescription: String? {
            switch self {
            case .undecodable(let file):
                String(localized: "Couldn't decode “\(file)”. This version of macOS may not support its audio format.")
            case .silent:
                String(localized: "None of the pack's sounds could be loaded.")
            }
        }
    }

    /// Longest single key sound kept from a per-key file.
    private static let maxClipDuration: Double = 3

    static func load(_ id: KeyPackID, folder: URL?, sampleRate: Double) throws -> LoadedKeyPack {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2) else {
            throw LoadError.silent
        }
        switch id {
        case .builtin(let profile):
            let pack = KeyClickSynth.pack(profile, name: profile.rawValue)
            var buffers: [KeySoundPack.Clip: AVAudioPCMBuffer] = [:]
            for clip in pack.allClips {
                guard case .synth(let sound) = clip else { continue }
                buffers[clip] = SampleDecoder.buffer(mono: KeyClickSynth.render(sound, sampleRate: sampleRate), format: format)
            }
            return LoadedKeyPack(id: id, sampleRate: sampleRate, pack: pack, buffers: buffers)

        case .imported:
            guard let folder else { throw LoadError.silent }
            let parsed = try KeySoundPack.parseMechvibes(Data(contentsOf: folder.appending(path: "config.json")))
            // Some packs list files they do not contain; those keys use the pack's fallbacks.
            var pack = parsed.removingClips {
                guard case .file(let path) = $0 else { return false }
                return !FileManager.default.fileExists(atPath: folder.appending(path: path).path)
            }

            var buffers: [KeySoundPack.Clip: AVAudioPCMBuffer] = [:]
            var sprite: AVAudioPCMBuffer?
            if let spriteFile = pack.spriteFile {
                sprite = SampleDecoder.load(folder.appending(path: spriteFile), as: format, maxDuration: nil)
                if sprite == nil { throw LoadError.undecodable(spriteFile) }
            }
            for clip in pack.allClips {
                switch clip {
                case .slice(let start, let duration):
                    buffers[clip] = sprite.flatMap { SampleDecoder.slice($0, startMs: start, durationMs: duration) }
                case .file(let path):
                    buffers[clip] = SampleDecoder.load(folder.appending(path: path), as: format, maxDuration: maxClipDuration)
                case .synth:
                    break
                }
            }
            pack = pack.removingClips { buffers[$0] == nil }
            guard !buffers.isEmpty else { throw LoadError.silent }
            return LoadedKeyPack(id: id, sampleRate: sampleRate, pack: pack, buffers: buffers)
        }
    }
}
