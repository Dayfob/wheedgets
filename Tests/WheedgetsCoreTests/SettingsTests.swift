import Carbon.HIToolbox
import Foundation
import Testing
@testable import WheedgetsCore

struct SettingsTests {
    @Test func defaultKitUsesUniqueNonReservedKeys() {
        let pads = Pad.makeDefaultKit()
        #expect(Set(pads.map(\.keyCode)).count == pads.count)
        #expect(!pads.contains { $0.keyCode == KeyCodes.escape })
    }

    @Test func defaultShortcutHasAModifier() {
        #expect(Hotkey.toggleDefault.modifiers.isValidForShortcut)
        #expect(Hotkey.toggleDefault.modifiers.symbols == "⌃⌥")
    }

    @Test func roundTripsThroughJSON() throws {
        var settings = AppSettings()
        settings.masterVolume = 0.7
        settings.drums.volume = 1.4
        settings.drums.keyHandling = .passThrough
        settings.widgets.selected = .spinner
        settings.spinner.color = .sage
        settings.drums.pads[0].source = .sample(fileName: "abc.wav", displayName: "My Snare")
        let data = try JSONEncoder().encode(settings)
        #expect(try JSONDecoder().decode(AppSettings.self, from: data) == settings)
    }

    @Test func missingFieldsFallBackToDefaults() throws {
        let json = #"{"masterVolume": 3, "drums": {"volume": 5, "keyHandling": "someFutureMode"}}"#
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        #expect(settings.masterVolume == Volume.master.upperBound, "out-of-range volume is clamped")
        #expect(settings.drums.volume == Volume.module.upperBound)
        #expect(settings.drums.keyHandling == .capture, "unknown values fall back")
        #expect(settings.widgets == WidgetHostSettings())
        #expect(settings.drums.pads.count == Pad.makeDefaultKit().count)
    }

    @Test func readsSettingsWrittenByOlderVersions() throws {
        let json = #"{"playMode": {"hotkey": {"keyCode": 42, "modifiers": 256}, "instrument": "drums"}, "keyboardSounds": {"enabled": true, "pack": "builtin:thocky"}}"#
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        #expect(settings.widgets.hotkey.keyCode == 42)
        #expect(settings.widgets.selected == .drums)
        #expect(settings.keyboardSounds.pack == .builtin(.thocky))

        let reencoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        #expect(reencoded == settings)
    }

    @Test func assigningATakenKeySwapsKeys() {
        let snare = Pad(keyCode: UInt16(kVK_ANSI_J), source: .builtin(.snare))
        let kick = Pad(keyCode: UInt16(kVK_ANSI_F), source: .builtin(.kick))
        var drums = DrumSettings(pads: [snare, kick])

        drums.assignKey(UInt16(kVK_ANSI_F), toPad: snare.id)

        #expect(drums.pads[0].keyCode == UInt16(kVK_ANSI_F))
        #expect(drums.pads[1].keyCode == UInt16(kVK_ANSI_J))
    }

    @Test func escapeCannotBeAssigned() {
        let pad = Pad(keyCode: UInt16(kVK_ANSI_J), source: .builtin(.snare))
        var drums = DrumSettings(pads: [pad])
        drums.assignKey(KeyCodes.escape, toPad: pad.id)
        #expect(drums.pads[0].keyCode == UInt16(kVK_ANSI_J))
    }

    @Test func addPadPicksAFreeKeyAndStopsWhenFull() {
        var drums = DrumSettings(pads: [])
        for _ in KeyCodes.bindingCandidates {
            #expect(drums.addPad() != nil)
        }
        #expect(drums.addPad() == nil)
        #expect(Set(drums.pads.map(\.keyCode)).count == drums.pads.count)
    }
}
