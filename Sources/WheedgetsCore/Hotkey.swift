import Carbon.HIToolbox

/// Modifier flags using Carbon's bit layout, which is what `RegisterEventHotKey` expects.
public struct Modifiers: OptionSet, Codable, Hashable, Sendable {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }

    public static let command = Modifiers(rawValue: UInt32(cmdKey))
    public static let shift = Modifiers(rawValue: UInt32(shiftKey))
    public static let option = Modifiers(rawValue: UInt32(optionKey))
    public static let control = Modifiers(rawValue: UInt32(controlKey))

    /// Symbols in the order macOS menus use: ⌃⌥⇧⌘.
    public var symbols: String {
        var result = ""
        if contains(.control) { result += "⌃" }
        if contains(.option) { result += "⌥" }
        if contains(.shift) { result += "⇧" }
        if contains(.command) { result += "⌘" }
        return result
    }

    /// A global shortcut needs at least one of ⌘ ⌃ ⌥; Shift alone would clash with typing.
    public var isValidForShortcut: Bool {
        !intersection([.command, .control, .option]).isEmpty
    }
}

/// A global keyboard shortcut.
public struct Hotkey: Codable, Hashable, Sendable {
    public var keyCode: UInt16
    public var modifiers: Modifiers

    public init(keyCode: UInt16, modifiers: Modifiers) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// ⌃⌥W — "W" for Wheedgets.
    public static let toggleDefault = Hotkey(keyCode: UInt16(kVK_ANSI_W), modifiers: [.control, .option])
}

public enum KeyCodes {
    public static let escape = UInt16(kVK_Escape)

    /// Keys offered to new bindings, in the order they are handed out.
    public static let bindingCandidates: [UInt16] = [
        kVK_ANSI_Q, kVK_ANSI_W, kVK_ANSI_E, kVK_ANSI_R, kVK_ANSI_T, kVK_ANSI_Y, kVK_ANSI_U, kVK_ANSI_I,
        kVK_ANSI_O, kVK_ANSI_P, kVK_ANSI_A, kVK_ANSI_S, kVK_ANSI_D, kVK_ANSI_F, kVK_ANSI_G, kVK_ANSI_H,
        kVK_ANSI_J, kVK_ANSI_K, kVK_ANSI_L, kVK_ANSI_Z, kVK_ANSI_X, kVK_ANSI_C, kVK_ANSI_V, kVK_ANSI_B,
        kVK_ANSI_N, kVK_ANSI_M, kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5, kVK_ANSI_6,
        kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9, kVK_ANSI_0
    ].map { UInt16($0) }
}

public extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
