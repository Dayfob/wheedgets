import Testing
@testable import WheedgetsCore

struct PressedKeysTests {
    @Test func holdingAKeyMarksFollowingKeyDownsAsRepeats() {
        var keys = PressedKeys()
        #expect(keys.register(keyCode: 0, isDown: true) == false)
        #expect(keys.register(keyCode: 0, isDown: true) == true)
        #expect(keys.register(keyCode: 0, isDown: true) == true)
        #expect(keys.register(keyCode: 0, isDown: false) == false)
        #expect(keys.register(keyCode: 0, isDown: true) == false, "a new press after release")
    }

    @Test func keysAreTrackedIndependently() {
        var keys = PressedKeys()
        #expect(keys.register(keyCode: 0, isDown: true) == false)
        #expect(keys.register(keyCode: 1, isDown: true) == false, "rolling over to another key")
        #expect(keys.register(keyCode: 0, isDown: true) == true)
    }

    @Test func resetForgetsHeldKeys() {
        var keys = PressedKeys()
        _ = keys.register(keyCode: 0, isDown: true)
        keys.reset()
        #expect(keys.register(keyCode: 0, isDown: true) == false)
    }
}
