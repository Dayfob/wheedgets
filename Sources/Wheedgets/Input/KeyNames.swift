import AppKit
import Carbon.HIToolbox
import WheedgetsCore

/// Human-readable names for virtual key codes.
@MainActor
enum KeyNames {
    static func name(for keyCode: UInt16) -> String {
        if let special = specialKeys[Int(keyCode)] { return special }
        return layoutCharacter(for: keyCode)?.uppercased() ?? "#\(keyCode)"
    }

    /// Translates through the current ASCII-capable layout, so keys read as
    /// Latin letters (J, not О) even while a Russian layout is active.
    private static func layoutCharacter(for keyCode: UInt16) -> String? {
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let property = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let layoutData = Unmanaged<CFData>.fromOpaque(property).takeUnretainedValue() as Data

        return layoutData.withUnsafeBytes { raw -> String? in
            guard let layout = raw.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return nil }
            var deadKeyState: UInt32 = 0
            var characters = [UniChar](repeating: 0, count: 4)
            var length = 0
            let status = UCKeyTranslate(
                layout,
                keyCode,
                UInt16(kUCKeyActionDisplay),
                0,
                UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState,
                characters.count,
                &length,
                &characters
            )
            guard status == noErr, length > 0 else { return nil }
            let string = String(utf16CodeUnits: characters, count: length)
            return string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : string
        }
    }

    private static let specialKeys: [Int: String] = [
        kVK_Space: String(localized: "Space"),
        kVK_Return: "↩", kVK_ANSI_KeypadEnter: "⌤", kVK_Tab: "⇥",
        kVK_Delete: "⌫", kVK_ForwardDelete: "⌦", kVK_Escape: "⎋",
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
        kVK_F13: "F13", kVK_F14: "F14", kVK_F15: "F15", kVK_F16: "F16", kVK_F17: "F17",
        kVK_F18: "F18", kVK_F19: "F19", kVK_F20: "F20",
        kVK_ANSI_Keypad0: "Num 0", kVK_ANSI_Keypad1: "Num 1", kVK_ANSI_Keypad2: "Num 2",
        kVK_ANSI_Keypad3: "Num 3", kVK_ANSI_Keypad4: "Num 4", kVK_ANSI_Keypad5: "Num 5",
        kVK_ANSI_Keypad6: "Num 6", kVK_ANSI_Keypad7: "Num 7", kVK_ANSI_Keypad8: "Num 8",
        kVK_ANSI_Keypad9: "Num 9", kVK_ANSI_KeypadDecimal: "Num .", kVK_ANSI_KeypadPlus: "Num +",
        kVK_ANSI_KeypadMinus: "Num −", kVK_ANSI_KeypadMultiply: "Num ×", kVK_ANSI_KeypadDivide: "Num ÷",
        kVK_ANSI_KeypadEquals: "Num =", kVK_ANSI_KeypadClear: "Num ⌧"
    ]
}

extension Hotkey {
    @MainActor
    var displayName: String {
        modifiers.symbols + KeyNames.name(for: keyCode)
    }
}

extension Modifiers {
    init(_ flags: NSEvent.ModifierFlags) {
        var modifiers: Modifiers = []
        if flags.contains(.command) { modifiers.insert(.command) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.control) { modifiers.insert(.control) }
        self = modifiers
    }

    var eventFlags: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if contains(.command) { flags.insert(.command) }
        if contains(.shift) { flags.insert(.shift) }
        if contains(.option) { flags.insert(.option) }
        if contains(.control) { flags.insert(.control) }
        return flags
    }
}
