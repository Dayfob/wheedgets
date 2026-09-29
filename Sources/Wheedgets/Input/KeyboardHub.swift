import CoreGraphics
import WheedgetsCore

struct KeyEvent: Sendable {
    let keyCode: UInt16
    let flags: CGEventFlags
    let isDown: Bool
    var isRepeat: Bool
    /// Shift, Control, Option, Command, Caps Lock or Fn.
    let isModifier: Bool

    /// ⌘, ⌃ or ⌥ held: the press is a shortcut, not typing.
    var hasShortcutModifier: Bool {
        !flags.isDisjoint(with: [.maskCommand, .maskControl, .maskAlternate])
    }
}

/// Owns the single keyboard event tap and shares it between modules.
///
/// The tap exists only while at least one module holds it, so with every
/// module idle the app sees no keystrokes at all. It runs as a filtering tap
/// only while some holder may swallow keys; otherwise it only listens, which
/// never holds up typing.
///
/// Filters run first, in the order they were added; the first one that returns
/// true swallows the event. Listeners then see every event nobody swallowed.
@MainActor
final class KeyboardHub {
    typealias Filter = (KeyEvent) -> Bool
    typealias Listener = (KeyEvent) -> Void

    private let interceptor = KeyInterceptor()
    private var filters: [Filter] = []
    private var listeners: [Listener] = []
    private var holders: [String: KeyInterceptor.Mode] = [:]
    private var pressedKeys = PressedKeys()

    init() {
        interceptor.handler = { [weak self] event in
            self?.dispatch(event) ?? false
        }
    }

    func addFilter(_ filter: @escaping Filter) {
        filters.append(filter)
    }

    func addListener(_ listener: @escaping Listener) {
        listeners.append(listener)
    }

    /// Returns false when macOS refuses the tap (Accessibility access missing or stale).
    func acquire(for holder: String, mode: KeyInterceptor.Mode) -> Bool {
        var wanted = holders
        wanted[holder] = mode
        guard interceptor.start(Self.mode(for: wanted)!) else { return false }
        holders = wanted
        return true
    }

    func release(for holder: String) {
        holders[holder] = nil
        if let mode = Self.mode(for: holders) {
            _ = interceptor.start(mode)
        } else {
            interceptor.stop()
            // Key-ups while stopped are never seen.
            pressedKeys.reset()
        }
    }

    private static func mode(for holders: [String: KeyInterceptor.Mode]) -> KeyInterceptor.Mode? {
        if holders.isEmpty { return nil }
        return holders.values.contains(.filter) ? .filter : .listen
    }

    private func dispatch(_ event: KeyEvent) -> Bool {
        var event = event
        if !event.isModifier && pressedKeys.register(keyCode: event.keyCode, isDown: event.isDown) {
            event.isRepeat = true
        }
        for filter in filters where filter(event) {
            return true
        }
        for listener in listeners {
            listener(event)
        }
        return false
    }
}
