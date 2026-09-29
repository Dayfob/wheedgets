import Carbon.HIToolbox

/// Mechvibes packs name keys by "standard" key codes (PC scan codes as
/// reported by iohook: Esc = 1, A = 30, Space = 57, arrows in the 57 4xx range).
/// This maps macOS virtual key codes onto them.
public enum MechvibesKeyCodes {
    public static let space = 57
    public static let enter = 28
    public static let keypadEnter = 3612
    public static let backspace = 14
    /// A key every pack defines; used when a pack has no sound for a key.
    public static let generic = 30

    public static let modifiers: Set<Int> = [42, 54, 29, 3613, 56, 3640, 3675, 3676, 58]

    public static func code(for keyCode: UInt16) -> Int? {
        table[Int(keyCode)]
    }

    public static var allCodes: Set<Int> { Set(table.values) }

    private static let table: [Int: Int] = [
        kVK_Escape: 1,
        kVK_F1: 59, kVK_F2: 60, kVK_F3: 61, kVK_F4: 62, kVK_F5: 63, kVK_F6: 64,
        kVK_F7: 65, kVK_F8: 66, kVK_F9: 67, kVK_F10: 68, kVK_F11: 87, kVK_F12: 88,
        kVK_F13: 91, kVK_F14: 92, kVK_F15: 93,

        kVK_ANSI_Grave: 41,
        kVK_ANSI_1: 2, kVK_ANSI_2: 3, kVK_ANSI_3: 4, kVK_ANSI_4: 5, kVK_ANSI_5: 6,
        kVK_ANSI_6: 7, kVK_ANSI_7: 8, kVK_ANSI_8: 9, kVK_ANSI_9: 10, kVK_ANSI_0: 11,
        kVK_ANSI_Minus: 12, kVK_ANSI_Equal: 13, kVK_Delete: 14,

        kVK_Tab: 15, kVK_CapsLock: 58,
        kVK_ANSI_Q: 16, kVK_ANSI_W: 17, kVK_ANSI_E: 18, kVK_ANSI_R: 19, kVK_ANSI_T: 20,
        kVK_ANSI_Y: 21, kVK_ANSI_U: 22, kVK_ANSI_I: 23, kVK_ANSI_O: 24, kVK_ANSI_P: 25,
        kVK_ANSI_LeftBracket: 26, kVK_ANSI_RightBracket: 27, kVK_ANSI_Backslash: 43,
        kVK_ANSI_A: 30, kVK_ANSI_S: 31, kVK_ANSI_D: 32, kVK_ANSI_F: 33, kVK_ANSI_G: 34,
        kVK_ANSI_H: 35, kVK_ANSI_J: 36, kVK_ANSI_K: 37, kVK_ANSI_L: 38,
        kVK_ANSI_Semicolon: 39, kVK_ANSI_Quote: 40, kVK_Return: 28,
        kVK_ANSI_Z: 44, kVK_ANSI_X: 45, kVK_ANSI_C: 46, kVK_ANSI_V: 47, kVK_ANSI_B: 48,
        kVK_ANSI_N: 49, kVK_ANSI_M: 50,
        kVK_ANSI_Comma: 51, kVK_ANSI_Period: 52, kVK_ANSI_Slash: 53,
        kVK_Space: 57,

        kVK_Shift: 42, kVK_RightShift: 54, kVK_Control: 29, kVK_RightControl: 3613,
        kVK_Option: 56, kVK_RightOption: 3640, kVK_Command: 3675, kVK_RightCommand: 3676,

        kVK_Help: 3666, kVK_ForwardDelete: 3667, kVK_Home: 3655, kVK_End: 3663,
        kVK_PageUp: 3657, kVK_PageDown: 3665,
        kVK_UpArrow: 57416, kVK_LeftArrow: 57419, kVK_RightArrow: 57421, kVK_DownArrow: 57424,

        kVK_ANSI_KeypadClear: 69, kVK_ANSI_KeypadDivide: 3637, kVK_ANSI_KeypadMultiply: 55,
        kVK_ANSI_KeypadMinus: 74, kVK_ANSI_KeypadEquals: 3597, kVK_ANSI_KeypadPlus: 78,
        kVK_ANSI_KeypadEnter: 3612, kVK_ANSI_KeypadDecimal: 83,
        kVK_ANSI_Keypad1: 79, kVK_ANSI_Keypad2: 80, kVK_ANSI_Keypad3: 81, kVK_ANSI_Keypad4: 75,
        kVK_ANSI_Keypad5: 76, kVK_ANSI_Keypad6: 77, kVK_ANSI_Keypad7: 71, kVK_ANSI_Keypad8: 72,
        kVK_ANSI_Keypad9: 73, kVK_ANSI_Keypad0: 82
    ]
}
