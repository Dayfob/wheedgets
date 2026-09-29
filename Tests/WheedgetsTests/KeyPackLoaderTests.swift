import Foundation
import Testing
@testable import Wheedgets
@testable import WheedgetsCore

struct KeyPackLoaderTests {
    @Test(arguments: KeyClickSynth.Profile.allCases)
    func loadsBuiltinPacks(profile: KeyClickSynth.Profile) throws {
        let loaded = try KeyPackLoader.load(.builtin(profile), folder: nil, sampleRate: 48_000)
        for code in MechvibesKeyCodes.allCodes {
            #expect(loaded.buffer(for: code, phase: .press) != nil)
            #expect(loaded.buffer(for: code, phase: .release) != nil)
        }
    }

    /// Decodes real packs (Ogg sprites and per-key MP3s).
    /// Run with `MECHVIBES_PACKS=/path/to/mechvibes/src/audio swift test`.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["MECHVIBES_PACKS"] != nil))
    func loadsRealMechvibesPacks() throws {
        let root = URL(fileURLWithPath: ProcessInfo.processInfo.environment["MECHVIBES_PACKS"]!)
        let folders = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .filter { FileManager.default.fileExists(atPath: $0.appending(path: "config.json").path) }
        #expect(!folders.isEmpty)
        for folder in folders {
            let loaded = try KeyPackLoader.load(.imported(folder.lastPathComponent), folder: folder, sampleRate: 48_000)
            let buffer = try #require(loaded.buffer(for: MechvibesKeyCodes.generic, phase: .press), "\(folder.lastPathComponent)")
            #expect(buffer.frameLength > 100, "\(folder.lastPathComponent)")
            #expect(buffer.format.sampleRate == 48_000)
            #expect(loaded.buffer(for: MechvibesKeyCodes.space, phase: .press) != nil, "\(folder.lastPathComponent)")
        }
    }
}
