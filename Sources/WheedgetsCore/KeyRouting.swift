/// Decides what a widget in capture mode does with one key event.
/// (In pass-through mode nothing is swallowed and the widget sees every key.)
public enum KeyRouting {
    public enum Outcome: Equatable, Sendable {
        /// Not the widget's business: deliver the key normally.
        case ignore
        /// Esc: turn the widget off and swallow the Esc.
        case turnOff
        /// A bound key: the widget reacts and the key is swallowed.
        case capture
    }

    /// - Parameters:
    ///   - hasShortcutModifier: ⌘, ⌃ or ⌥ is held. Such presses are shortcuts
    ///     (including the widget toggle) and always pass through untouched.
    ///   - isBound: the widget has something bound to this key.
    public static func routeCaptured(keyCode: UInt16, hasShortcutModifier: Bool, isBound: Bool) -> Outcome {
        if hasShortcutModifier { return .ignore }
        if keyCode == KeyCodes.escape { return .turnOff }
        return isBound ? .capture : .ignore
    }
}
