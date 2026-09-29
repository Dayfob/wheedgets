import Carbon.HIToolbox
import Testing
@testable import WheedgetsCore

struct KeyRoutingTests {
    private let j = UInt16(kVK_ANSI_J)

    @Test func boundKeysAreCaptured() {
        #expect(KeyRouting.routeCaptured(keyCode: j, hasShortcutModifier: false, isBound: true) == .capture)
    }

    @Test func unboundKeysAreIgnored() {
        #expect(KeyRouting.routeCaptured(keyCode: j, hasShortcutModifier: false, isBound: false) == .ignore)
    }

    @Test func shortcutsAlwaysPassThrough() {
        #expect(KeyRouting.routeCaptured(keyCode: j, hasShortcutModifier: true, isBound: true) == .ignore)
        #expect(KeyRouting.routeCaptured(keyCode: KeyCodes.escape, hasShortcutModifier: true, isBound: false) == .ignore)
    }

    @Test func escapeTurnsTheWidgetOff() {
        #expect(KeyRouting.routeCaptured(keyCode: KeyCodes.escape, hasShortcutModifier: false, isBound: false) == .turnOff)
    }
}
