import AppKit
import Observation
import OSLog
import WheedgetsCore

/// A fidget widget. The host turns exactly one of them on at a time.
@MainActor
protocol Widget: AnyObject {
    var kind: WidgetKind { get }
    /// False when the widget is driven by something else (e.g. the trackpad):
    /// then no keyboard tap is created at all.
    var usesKeyboard: Bool { get }
    /// Capture: bound keys are swallowed. Pass-through: every key still types,
    /// and the widget sees all of them (its own keys, typing, shortcuts).
    var keyHandling: KeyHandling { get }
    /// In capture mode, whether this key belongs to the widget.
    func isBound(_ keyCode: UInt16) -> Bool
    func handleKey(_ event: KeyEvent)
    var volume: Float { get set }
    func widgetDidTurnOn()
    func widgetDidTurnOff()
}

extension Widget {
    var usesKeyboard: Bool { true }
}

/// Owns the selected widget, the single on/off shortcut and the keyboard tap.
@MainActor
@Observable
final class WidgetHost {
    enum State: Equatable {
        case off
        case on
        /// Turned on, but Accessibility access is not granted yet.
        case waitingForPermission
    }

    private static let tapHolder = "widget"

    private(set) var state: State = .off

    var settings: WidgetHostSettings {
        didSet {
            if settings.hotkey != oldValue.hotkey { updateHotkeyRegistration() }
            onChange()
        }
    }

    private(set) var hotkeyAvailable = true

    /// The key recorder currently listening, if any. While set, the shortcut
    /// and the widget step aside so the recorder gets the keys.
    var activeRecorder: UUID? {
        didSet { updateHotkeyRegistration() }
    }

    @ObservationIgnored var onChange: () -> Void = {}
    @ObservationIgnored let accessibility: AccessibilityStatus
    @ObservationIgnored private let widgets: [WidgetKind: any Widget]
    @ObservationIgnored private let keyboard: KeyboardHub
    @ObservationIgnored private var hotkey: GlobalHotkey?
    @ObservationIgnored private var tapMode: KeyInterceptor.Mode?

    init(settings: WidgetHostSettings, widgets: [any Widget], keyboard: KeyboardHub, accessibility: AccessibilityStatus) {
        self.settings = settings
        self.widgets = Dictionary(uniqueKeysWithValues: widgets.map { ($0.kind, $0) })
        self.keyboard = keyboard
        self.accessibility = accessibility
        keyboard.addFilter { [weak self] event in self?.filter(event) ?? false }
        hotkey = GlobalHotkey { [weak self] in self?.toggle() }
        updateHotkeyRegistration()
    }

    var selected: any Widget {
        widgets[settings.selected]!
    }

    func widget(_ kind: WidgetKind) -> any Widget {
        widgets[kind]!
    }

    // MARK: - On / off

    func toggle() {
        Logger.app.notice("Toggle: \(String(describing: self.state), privacy: .public) → switching")
        state == .off ? turnOn() : turnOff()
    }

    /// Selects a widget and turns it on (the menu's "switch to").
    func switchTo(_ kind: WidgetKind) {
        guard kind != settings.selected || state == .off else { return }
        let wasOn = state == .on
        if wasOn { selected.widgetDidTurnOff() }
        settings.selected = kind
        if wasOn {
            updateTap()
            selected.widgetDidTurnOn()
        } else {
            turnOn()
        }
    }

    func turnOn() {
        accessibility.refresh()
        guard accessibility.isTrusted else {
            Logger.app.notice("Turn on: Accessibility not trusted, waiting")
            state = .waitingForPermission
            accessibility.waitForGrant(owner: Self.tapHolder) { [weak self] granted in
                guard let self, self.state == .waitingForPermission else { return }
                if granted { self.turnOn() } else { self.state = .off }
            }
            return
        }
        state = .on
        Logger.app.notice("Turn on: \(self.settings.selected.rawValue, privacy: .public)")
        guard updateTap() else {
            state = .off
            Alerts.stalePermission()
            return
        }
        selected.widgetDidTurnOn()
    }

    func turnOff() {
        accessibility.cancelWait(owner: Self.tapHolder)
        if state == .on { selected.widgetDidTurnOff() }
        state = .off
        updateTap()
    }

    /// Call when the selected widget's key handling or input changes while it is on.
    func keyHandlingDidChange() {
        if state == .on { updateTap() }
    }

    /// A pass-through widget never swallows keys, so it gets a listen-only
    /// tap, which can't delay typing; capture needs a filtering tap.
    @discardableResult
    private func updateTap() -> Bool {
        guard state == .on, selected.usesKeyboard else {
            keyboard.release(for: Self.tapHolder)
            tapMode = nil
            return true
        }
        let mode: KeyInterceptor.Mode = selected.keyHandling == .capture ? .filter : .listen
        guard mode != tapMode else { return true }
        guard keyboard.acquire(for: Self.tapHolder, mode: mode) else { return false }
        tapMode = mode
        return true
    }

    // MARK: - Keys

    private func filter(_ event: KeyEvent) -> Bool {
        guard state == .on, activeRecorder == nil else { return false }
        let widget = selected
        guard widget.keyHandling == .capture else {
            widget.handleKey(event)
            return false
        }
        guard !event.isModifier else { return false }
        switch KeyRouting.routeCaptured(
            keyCode: event.keyCode,
            hasShortcutModifier: event.hasShortcutModifier,
            isBound: widget.isBound(event.keyCode)
        ) {
        case .ignore:
            return false
        case .turnOff:
            if event.isDown { turnOff() }
            return true
        case .capture:
            widget.handleKey(event)
            return true
        }
    }

    private func updateHotkeyRegistration() {
        guard let hotkey else { return }
        if activeRecorder != nil {
            hotkey.unregister()
        } else {
            hotkeyAvailable = hotkey.register(settings.hotkey)
        }
    }
}

extension WidgetKind {
    var displayName: String {
        switch self {
        case .drums: String(localized: "Drums")
        case .spinner: String(localized: "Spinner")
        case .keyboardSounds: String(localized: "Keyboard Sounds")
        }
    }

    var systemImage: String {
        switch self {
        case .drums: "circle.grid.3x3.fill"
        case .spinner: "fanblades.fill"
        case .keyboardSounds: "keyboard"
        }
    }
}
