import Carbon.HIToolbox
import Foundation
import Testing
@testable import WheedgetsCore

struct KeySoundPackTests {
    // Shapes taken from packs that ship with Mechvibes.
    private let singleV1 = #"""
    {
      "id": "custom-sound-pack-1582654366773",
      "name": "CherryMX Black - ABS keycaps",
      "key_define_type": "single",
      "includes_numpad": false,
      "sound": "sound.ogg",
      "defines": {
        "1": [2926, 125],
        "1-up": [3051, 77],
        "30": [13470, 128],
        "57": null
      }
    }
    """#

    private let multiV2 = #"""
    {
      "id": "custom-sound-pack-1720300926821",
      "name": "MX Brown - Full Travel",
      "key_define_type": "multi",
      "sound": "press/GENERIC_R{0-4}.mp3",
      "soundup": "release/GENERIC.mp3",
      "defines": {
        "14": "press/BACKSPACE.mp3",
        "14-up": "release/BACKSPACE.mp3",
        "57": "press/SPACE.mp3"
      },
      "version": 2
    }
    """#

    @Test func parsesSingleSpritePacks() throws {
        let pack = try KeySoundPack.parseMechvibes(Data(singleV1.utf8))
        #expect(pack.name == "CherryMX Black - ABS keycaps")
        #expect(pack.spriteFile == "sound.ogg")
        #expect(pack.clips(for: 1, phase: .press) == [.slice(startMs: 2926, durationMs: 125)])
        #expect(pack.clips(for: 1, phase: .release) == [.slice(startMs: 3051, durationMs: 77)])
        #expect(pack.referencedFiles == ["sound.ogg"])
    }

    @Test func undefinedKeysFallBackToTheSoundOfA() throws {
        let pack = try KeySoundPack.parseMechvibes(Data(singleV1.utf8))
        // Space is null in the pack, arrows are missing entirely.
        #expect(pack.clips(for: 57, phase: .press) == [.slice(startMs: 13470, durationMs: 128)])
        #expect(pack.clips(for: 57416, phase: .press) == [.slice(startMs: 13470, durationMs: 128)])
        #expect(pack.clips(for: 57, phase: .release).isEmpty, "no release sound for A either")
    }

    @Test func parsesMultiFilePacksWithRandomRangesAndFallbacks() throws {
        let pack = try KeySoundPack.parseMechvibes(Data(multiV2.utf8))
        #expect(pack.clips(for: 14, phase: .press) == [.file("press/BACKSPACE.mp3")])
        #expect(pack.clips(for: 14, phase: .release) == [.file("release/BACKSPACE.mp3")])
        #expect(pack.clips(for: 30, phase: .press) == (0...4).map { .file("press/GENERIC_R\($0).mp3") })
        #expect(pack.clips(for: 30, phase: .release) == [.file("release/GENERIC.mp3")])
        #expect(pack.referencedFiles.count == 9)
    }

    @Test func versionOneMultiPacksHaveNoFileFallback() throws {
        let json = #"{"name": "NK Cream", "key_define_type": "multi", "sound": "sound.ogg", "defines": {"30": "a.wav", "57": "space.wav"}}"#
        let pack = try KeySoundPack.parseMechvibes(Data(json.utf8))
        #expect(pack.fallbackPress.isEmpty)
        #expect(pack.clips(for: 31, phase: .press) == [.file("a.wav")])
    }

    @Test func missingFilesFallBackToThePackDefault() throws {
        let pack = try KeySoundPack.parseMechvibes(Data(multiV2.utf8))
            .removingClips { $0 == .file("press/BACKSPACE.mp3") }
        #expect(pack.clips(for: 14, phase: .press) == (0...4).map { .file("press/GENERIC_R\($0).mp3") })
        #expect(pack.clips(for: 14, phase: .release) == [.file("release/BACKSPACE.mp3")])
    }

    @Test func rejectsPathsOutsideThePack() {
        let json = #"{"name": "Evil", "key_define_type": "multi", "defines": {"30": "../../secret.wav"}}"#
        #expect(throws: KeySoundPack.ParseError.unsafePath("../../secret.wav")) {
            try KeySoundPack.parseMechvibes(Data(json.utf8))
        }
    }

    @Test func rejectsBrokenConfigs() {
        #expect(throws: KeySoundPack.ParseError.notJSON) { try KeySoundPack.parseMechvibes(Data("nope".utf8)) }
        #expect(throws: KeySoundPack.ParseError.missingField("name")) {
            try KeySoundPack.parseMechvibes(Data(#"{"key_define_type": "single", "defines": {}}"#.utf8))
        }
        #expect(throws: KeySoundPack.ParseError.empty) {
            try KeySoundPack.parseMechvibes(Data(#"{"name": "x", "key_define_type": "single", "sound": "s.ogg", "defines": {}}"#.utf8))
        }
    }

    @Test func mapsMacKeysToMechvibesCodes() {
        #expect(MechvibesKeyCodes.code(for: UInt16(kVK_ANSI_A)) == 30)
        #expect(MechvibesKeyCodes.code(for: UInt16(kVK_Space)) == 57)
        #expect(MechvibesKeyCodes.code(for: UInt16(kVK_Return)) == 28)
        #expect(MechvibesKeyCodes.code(for: UInt16(kVK_UpArrow)) == 57416)
        #expect(MechvibesKeyCodes.code(for: UInt16(kVK_Command)) == 3675)
        #expect(MechvibesKeyCodes.allCodes.count > 100)
    }

    @Test func builtinPacksCoverEveryKey() {
        let pack = KeyClickSynth.pack(.clicky, name: "Clicky")
        for code in MechvibesKeyCodes.allCodes {
            #expect(!pack.clips(for: code, phase: .press).isEmpty)
            #expect(!pack.clips(for: code, phase: .release).isEmpty)
        }
    }

    @Test(arguments: KeyClickSynth.Profile.allCases)
    func synthesizedClicksAreShortAndClean(profile: KeyClickSynth.Profile) {
        for clip in KeyClickSynth.pack(profile, name: "").allClips {
            guard case .synth(let sound) = clip else { continue }
            let samples = KeyClickSynth.render(sound, sampleRate: 48_000)
            let peak = samples.reduce(Float(0)) { max($0, abs($1)) }
            #expect(samples.allSatisfy { $0.isFinite })
            #expect(peak > 0.3 && peak <= 0.8001)
            #expect(Double(samples.count) / 48_000 < 0.2)
        }
    }

    @Test func packIDsRoundTripAsStrings() throws {
        for id in [KeyPackID.builtin(.thocky), .imported("ABC-123")] {
            let data = try JSONEncoder().encode(id)
            #expect(try JSONDecoder().decode(KeyPackID.self, from: data) == id)
        }
        let unknown = try JSONDecoder().decode(KeyPackID.self, from: Data(#""builtin:marimba""#.utf8))
        #expect(unknown == .default)
    }
}

/// Parses real packs. Run with `MECHVIBES_PACKS=/path/to/mechvibes/src/audio swift test`.
struct MechvibesPackIntegrationTests {
    static let directory = ProcessInfo.processInfo.environment["MECHVIBES_PACKS"]

    @Test(.enabled(if: directory != nil))
    func parsesEveryPackAndFindsItsFiles() throws {
        let root = URL(fileURLWithPath: Self.directory!)
        let folders = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        var parsed = 0
        for folder in folders {
            let config = folder.appending(path: "config.json")
            guard FileManager.default.fileExists(atPath: config.path) else { continue }
            // Some shipped packs list files they do not contain; those clips are dropped.
            let pack = try KeySoundPack.parseMechvibes(Data(contentsOf: config)).removingClips {
                guard case .file(let path) = $0 else { return false }
                return !FileManager.default.fileExists(atPath: folder.appending(path: path).path)
            }
            for code in MechvibesKeyCodes.allCodes {
                #expect(!pack.clips(for: code, phase: .press).isEmpty, "\(pack.name): key \(code)")
            }
            parsed += 1
        }
        #expect(parsed > 0)
    }
}
