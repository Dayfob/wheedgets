import AppKit
import QuartzCore
import Observation
import WheedgetsCore

/// The fidget spinner widget: keys flick, push, brake and stop it; it whirs
/// louder the faster it turns, and coasts to a stop on its own.
@MainActor
@Observable
final class Spinner: Widget {
    let kind = WidgetKind.spinner

    var settings: SpinnerSettings {
        didSet { settingsDidChange(from: oldValue) }
    }

    /// Revolutions per second, for display.
    private(set) var speed = 0.0

    @ObservationIgnored var onChange: () -> Void = {}
    @ObservationIgnored var onKeyHandlingChange: () -> Void = {}
    @ObservationIgnored private var physics = SpinnerPhysics()
    @ObservationIgnored private let overlay = SpinnerOverlay()
    @ObservationIgnored private let audio: AudioEngine
    @ObservationIgnored private let sharedSpeed = SpinnerSpeed()
    @ObservationIgnored private var isOn = false
    /// Held spin keys and their direction; the last one pressed wins.
    @ObservationIgnored private var heldSpinKeys: [(key: UInt16, direction: Int)] = []
    @ObservationIgnored private var heldBrakeKeys: Set<UInt16> = []
    @ObservationIgnored private var lastSpeedPublish: CFTimeInterval = 0

    init(settings: SpinnerSettings, audio: AudioEngine) {
        self.settings = settings
        self.audio = audio
        audio.attachSource(SpinnerAudio.makeSourceNode(speed: sharedSpeed))
        sharedSpeed.setGain(settings.volume)
        physics.spinTime = settings.spinTime
        physics.pushStrength = settings.pushStrength
        physics.brakeStrength = settings.brakeStrength
        physics.touchBrakeStrength = settings.touchBrakeStrength

        overlay.view.onFrame = { [weak self] dt in self?.frame(dt) }
        MultitouchTrackpad.onActivity = { [weak self] in self?.wake() }
        overlay.configure(size: settings.size, color: settings.color)
        overlay.view.show(angle: 0, step: 0)
        overlay.onAppearanceChange = { [weak self] in
            guard let self else { return }
            self.overlay.configure(size: self.settings.size, color: self.settings.color)
            self.overlay.view.show(angle: self.physics.angle, step: 0)
        }
        updateVisibility()
    }

    // MARK: - Widget

    var keyHandling: KeyHandling { settings.keyHandling }

    var usesKeyboard: Bool { settings.control == .keyboard }

    var volume: Float {
        get { settings.volume }
        set { settings.volume = newValue }
    }

    func isBound(_ keyCode: UInt16) -> Bool {
        settings.role(of: keyCode) != .none
    }

    func handleKey(_ event: KeyEvent) {
        guard !event.isModifier, !event.isRepeat else { return }
        guard event.isDown else {
            release(key: event.keyCode)
            return
        }
        // Shortcuts (⌘C and friends) never spin it; plain typing may.
        guard !event.hasShortcutModifier else { return }

        let strength = settings.pushStrength
        switch settings.role(of: event.keyCode) {
        case .none:
            return
        case .action(let action):
            press(action, key: event.keyCode)
        case .typingNudge:
            physics.flick(direction: physics.currentDirection, strength: SpinnerPhysics.nudge * strength)
        case .typingBrake:
            // Mirrors a typing nudge, scaled by brake strength instead.
            physics.slow(by: SpinnerPhysics.nudge * settings.brakeStrength)
            holdBrake(key: event.keyCode)
        }
        wake()
    }

    func widgetDidTurnOn() {
        isOn = true
        updateTrackpad()
        updateVisibility()
    }

    func widgetDidTurnOff() {
        isOn = false
        updateTrackpad()
        heldSpinKeys.removeAll()
        heldBrakeKeys.removeAll()
        physics.pushDirection = 0
        physics.isBraking = false
        updateVisibility()
    }

    // MARK: - Controls

    private func press(_ action: SpinnerAction, key: UInt16) {
        switch action {
        case .spin:
            startPush(key: key, direction: physics.currentDirection)
        case .spinClockwise:
            startPush(key: key, direction: 1)
        case .spinCounterClockwise:
            startPush(key: key, direction: -1)
        case .brake:
            // Mirrors a flick, scaled by brake strength instead.
            physics.slow(by: SpinnerPhysics.flick * settings.brakeStrength)
            holdBrake(key: key)
        case .stop:
            heldSpinKeys.removeAll()
            physics.stop()
        }
    }

    private func startPush(key: UInt16, direction: Int) {
        physics.flick(direction: direction, strength: SpinnerPhysics.flick * settings.pushStrength)
        guard settings.holdKeepsGoing else { return }
        heldSpinKeys.removeAll { $0.key == key }
        heldSpinKeys.append((key, direction))
        physics.pushDirection = direction
    }

    /// A brake key keeps braking while held, if holding counts.
    private func holdBrake(key: UInt16) {
        guard settings.holdKeepsGoing else { return }
        heldBrakeKeys.insert(key)
        physics.isBraking = true
    }

    private func release(key: UInt16) {
        heldSpinKeys.removeAll { $0.key == key }
        physics.pushDirection = heldSpinKeys.last?.direction ?? 0
        heldBrakeKeys.remove(key)
        physics.isBraking = !heldBrakeKeys.isEmpty
    }

    /// A flick from Settings, to try the look and sound.
    func flick() {
        physics.flick(direction: physics.currentDirection, strength: SpinnerPhysics.flick * 3)
        wake()
    }

    func resetPosition() {
        overlay.resetPosition()
    }

    // MARK: - Animation

    private func wake() {
        updateVisibility()
        audio.setKeepAlive(true, owner: "spinner")
        if !overlay.view.isAnimating { overlay.view.setAnimating(true) }
    }

    private func frame(_ dt: Double) {
        if MultitouchTrackpad.isRunning {
            // Moving the spinner around the screen is not a gesture on it.
            let gesture = overlay.isDragging ? MultitouchTrackpad.Gesture() : MultitouchTrackpad.currentGesture()
            physics.setFinger(speed: gesture.speed, flicking: gesture.isFlicking)
            physics.touchHold = settings.touchBrakes ? gesture.hold : 0
            physics.isGrabbed = settings.touchBrakes && settings.touchStopsInstantly && gesture.isGrabbing
        }
        physics.step(dt)
        overlay.view.show(angle: physics.angle, step: physics.velocity * dt)
        sharedSpeed.set(physics.velocity)
        // The readout in Settings: ten updates a second is plenty, and each
        // one re-renders the form.
        let now = CACurrentMediaTime()
        if (now - lastSpeedPublish > 0.1 && abs(speed - physics.velocity) > 0.05) || (physics.velocity == 0 && speed != 0) {
            lastSpeedPublish = now
            speed = physics.velocity
        }
        if physics.isResting && !physics.isStopping {
            overlay.view.setAnimating(false)
            // Let the whir fade out before the engine may idle.
            audio.setKeepAlive(false, owner: "spinner")
            updateVisibility()
        }
    }

    /// Visible while on (or always, if chosen); after turning off it coasts
    /// to a stop in view, then fades away.
    private func updateVisibility() {
        let visible = isOn || settings.visibility == .always || !physics.isResting
        overlay.setVisible(visible)
    }

    // MARK: - Trackpad

    /// The trackpad is read only while the spinner is on and set to it.
    private func updateTrackpad() {
        if isOn && settings.control == .trackpad {
            MultitouchTrackpad.start(.spinner(sensitivity: settings.trackpadSensitivity), owner: "spinner")
        } else {
            MultitouchTrackpad.stop(owner: "spinner")
            physics.setFinger(speed: nil, flicking: false)
            physics.touchHold = 0
            physics.isGrabbed = false
        }
    }

    var trackpadAvailable: Bool { MultitouchTrackpad.isAvailable }

    // MARK: - Settings

    private func settingsDidChange(from old: SpinnerSettings) {
        if settings.size != old.size || settings.color != old.color {
            overlay.configure(size: settings.size, color: settings.color)
            overlay.view.show(angle: physics.angle, step: 0)
        }
        if settings.volume != old.volume { sharedSpeed.setGain(settings.volume) }
        if settings.spinTime != old.spinTime { physics.spinTime = settings.spinTime }
        if settings.pushStrength != old.pushStrength { physics.pushStrength = settings.pushStrength }
        if settings.brakeStrength != old.brakeStrength { physics.brakeStrength = settings.brakeStrength }
        if settings.touchBrakeStrength != old.touchBrakeStrength { physics.touchBrakeStrength = settings.touchBrakeStrength }
        if settings.visibility != old.visibility { updateVisibility() }
        if settings.keyHandling != old.keyHandling || settings.control != old.control { onKeyHandlingChange() }
        if settings.control != old.control { updateTrackpad() }
        if settings.trackpadSensitivity != old.trackpadSensitivity {
            MultitouchTrackpad.setSensitivity(settings.trackpadSensitivity)
        }
        onChange()
    }
}
