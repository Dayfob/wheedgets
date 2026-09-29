import SwiftUI
import WheedgetsCore

struct SpinnerSettingsView: View {
    @Bindable var spinner: Spinner
    let host: WidgetHost

    var body: some View {
        Form {
            Section {
                WidgetActivationRow(host: host, kind: .spinner)
                HStack {
                    Button("Give It a Spin", systemImage: "fanblades") { spinner.flick() }
                    Spacer()
                    Text(verbatim: String(format: "%.1f rev/s", abs(spinner.speed)))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Picker("Control", selection: $spinner.settings.control) {
                    Text("Keyboard").tag(SpinnerControl.keyboard)
                    Text("Trackpad").tag(SpinnerControl.trackpad)
                }
                .pickerStyle(.segmented)
            } footer: {
                Text(spinner.settings.control == .keyboard
                     ? "Keys spin it. The trackpad is left alone."
                     : "Finger movement on the trackpad spins it. Keys are left alone, and the trackpad keeps working as usual.")
                    .foregroundStyle(.secondary)
            }

            switch spinner.settings.control {
            case .keyboard:
                keyboardSections
            case .trackpad:
                trackpadSection
            }

            Section("Look") {
                LabeledContent("Color") {
                    HStack(spacing: 8) {
                        ForEach(SpinnerColor.allCases, id: \.self) { color in
                            ColorSwatch(color: color, isSelected: spinner.settings.color == color) {
                                spinner.settings.color = color
                            }
                        }
                    }
                }
                LabeledContent("Size") {
                    Slider(value: $spinner.settings.size, in: SpinnerSettings.sizeRange, step: 10)
                        .frame(width: 260)
                }
                Picker("Show", selection: $spinner.settings.visibility) {
                    Text("While it's on").tag(SpinnerVisibility.whilePlaying)
                    Text("Always").tag(SpinnerVisibility.always)
                }
                LabeledContent("Position") {
                    HStack {
                        Text("Drag the spinner to move it").foregroundStyle(.secondary)
                        Button("Reset") { spinner.resetPosition() }
                    }
                }
            }

            Section("Feel & Sound") {
                LabeledContent("Spin time") {
                    HStack {
                        Text("Short").font(.caption).foregroundStyle(.secondary)
                        Slider(value: $spinner.settings.spinTime, in: SpinnerSettings.spinTimeRange)
                        Text("Long").font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(width: 260)
                }
                LabeledContent("Volume") {
                    VolumeSlider(value: $spinner.settings.volume)
                        .frame(width: 260)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Spinner")
    }

    @ViewBuilder
    private var keyboardSections: some View {
        Section {
            Picker("Keys", selection: $spinner.settings.keyHandling) {
                Text("Only spin").tag(KeyHandling.capture)
                Text("Spin and type").tag(KeyHandling.passThrough)
            }
            .pickerStyle(.radioGroup)
            Toggle("Every key press spins it a little", isOn: $spinner.settings.spinsOnAnyKey)
            if spinner.settings.spinsOnAnyKey {
                LabeledContent("Keys that slow it down") {
                    TypingBrakeKeys(spinner: spinner, host: host)
                }
            }
        } footer: {
            Text(footer)
                .foregroundStyle(.secondary)
        }

        Section {
            ForEach(spinner.settings.bindings) { binding in
                BindingRow(spinner: spinner, host: host, binding: binding)
            }
            HStack {
                Button("Add Key", systemImage: "plus") {
                    if spinner.settings.addBinding() == nil { NSSound.beep() }
                }
                Spacer()
                Button("Restore Default Keys") { spinner.settings.bindings = SpinnerBinding.makeDefaults() }
            }
            LabeledContent("Push strength") {
                StrengthSlider(value: $spinner.settings.pushStrength)
            }
            LabeledContent("Brake strength") {
                StrengthSlider(value: $spinner.settings.brakeStrength)
            }
            Toggle("Holding a key keeps pushing or braking", isOn: $spinner.settings.holdKeepsGoing)
        } header: {
            Text("Keys")
        } footer: {
            Text(spinner.settings.holdKeepsGoing
                 ? "Hold a spin key to keep pushing, hold brake to slow down."
                 : "Each press counts once; holding a key does nothing more.")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var trackpadSection: some View {
        Section {
            if !spinner.trackpadAvailable {
                Label("This version of macOS doesn't give access to trackpad fingers.", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
            LabeledContent("Speed ratio") {
                HStack {
                    Slider(value: $spinner.settings.trackpadSensitivity, in: SpinnerSettings.strengthRange)
                    Text(verbatim: String(format: "×%.1f", spinner.settings.trackpadSensitivity))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 40, alignment: .trailing)
                }
                .frame(width: 260)
            }
            Toggle("Resting a finger slows it down", isOn: $spinner.settings.touchBrakes)
            if spinner.settings.touchBrakes {
                LabeledContent("Touch brake strength") {
                    HStack(spacing: 12) {
                        StrengthSlider(value: $spinner.settings.touchBrakeStrength)
                        Toggle("Instant", isOn: $spinner.settings.touchStopsInstantly)
                            .toggleStyle(.checkbox)
                            .help("A finger that lands and stays put stops it at once, like grabbing a real spinner. A finger that lands moving is a gesture.")
                    }
                }
            }
        } header: {
            Text("Trackpad")
        } footer: {
            Text("Move a finger around the trackpad's center: up on the right turns it counterclockwise, up on the left clockwise. A quick flick along the spin pushes it faster; a flick against it throws it the other way. Keep your finger moving and it follows your finger. At ×1 it feels like turning it by hand.")
                .foregroundStyle(.secondary)
        }
    }

    private var footer: LocalizedStringKey {
        switch (spinner.settings.keyHandling, spinner.settings.spinsOnAnyKey) {
        case (.capture, false): "Spinner keys don't type. Esc turns the spinner off."
        case (.capture, true): "Every key spins it and nothing types. Esc turns the spinner off."
        case (.passThrough, false): "Spinner keys spin it and still type. Turn it off with the shortcut."
        case (.passThrough, true): "Type as usual; your typing keeps it spinning."
        }
    }
}

private struct BindingRow: View {
    let spinner: Spinner
    let host: WidgetHost
    let binding: SpinnerBinding

    var body: some View {
        HStack(spacing: 12) {
            KeyRecorderButton(title: KeyNames.name(for: binding.keyCode), mode: .padKey, host: host) { keyCode, _ in
                spinner.settings.assignKey(keyCode, toBinding: binding.id)
            }
            .frame(width: 96)

            Picker("Action", selection: Binding(
                get: { binding.action },
                set: { action in
                    guard let index = spinner.settings.bindings.firstIndex(where: { $0.id == binding.id }) else { return }
                    spinner.settings.bindings[index].action = action
                }
            )) {
                ForEach(SpinnerAction.allCases, id: \.self) { action in
                    Text(action.displayName).tag(action)
                }
            }
            .labelsHidden()

            Spacer()

            Button(role: .destructive) {
                spinner.settings.bindings.removeAll { $0.id == binding.id }
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Remove key")
        }
    }
}

private struct StrengthSlider: View {
    @Binding var value: Double

    var body: some View {
        HStack {
            Text("Weak").font(.caption).foregroundStyle(.secondary)
            Slider(value: $value, in: SpinnerSettings.strengthRange)
            Text("Strong").font(.caption).foregroundStyle(.secondary)
        }
        .frame(width: 260)
    }
}

/// Chips for the typing brake keys, plus a recorder that adds one.
private struct TypingBrakeKeys: View {
    let spinner: Spinner
    let host: WidgetHost

    var body: some View {
        HStack(spacing: 6) {
            ForEach(spinner.settings.typingBrakeKeys, id: \.self) { keyCode in
                HStack(spacing: 4) {
                    Text(KeyNames.name(for: keyCode))
                        .font(.system(.body, design: .rounded).weight(.medium))
                    Button {
                        spinner.settings.typingBrakeKeys.removeAll { $0 == keyCode }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .help("Remove key")
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(.quaternary, in: Capsule())
            }
            KeyRecorderButton(title: String(localized: "Add…"), mode: .padKey, host: host) { keyCode, _ in
                spinner.settings.addTypingBrakeKey(keyCode)
            }
        }
    }
}

private struct ColorSwatch: View {
    let color: SpinnerColor
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        // Like the accent color picker in System Settings → Appearance.
        Button(action: action) {
            ZStack {
                Circle().fill(Color(nsColor: SpinnerArtwork.tint(for: color)))
                if isSelected {
                    Circle()
                        .fill(color.isLightFinish ? Color.black.opacity(0.6) : .white)
                        .frame(width: 6, height: 6)
                }
            }
            .frame(width: 18, height: 18)
            .overlay(Circle().strokeBorder(.black.opacity(0.12)))
        }
        .buttonStyle(.plain)
        .help(color.displayName)
        .accessibilityLabel(color.displayName)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

extension SpinnerAction {
    var displayName: String {
        switch self {
        case .spin: String(localized: "Spin")
        case .spinClockwise: String(localized: "Spin clockwise")
        case .spinCounterClockwise: String(localized: "Spin counterclockwise")
        case .brake: String(localized: "Brake")
        case .stop: String(localized: "Stop")
        }
    }
}

extension SpinnerColor {
    var displayName: String {
        switch self {
        case .cosmicOrange: String(localized: "Cosmic Orange")
        case .deepBlue: String(localized: "Deep Blue")
        case .silver: String(localized: "Silver")
        case .spaceBlack: String(localized: "Space Black")
        case .skyBlue: String(localized: "Sky Blue")
        case .lightGold: String(localized: "Light Gold")
        case .lavender: String(localized: "Lavender")
        case .mistBlue: String(localized: "Mist Blue")
        case .sage: String(localized: "Sage")
        case .pink: String(localized: "Pink")
        case .ultramarine: String(localized: "Ultramarine")
        case .teal: String(localized: "Teal")
        }
    }

    /// Pale finishes need a dark selection dot.
    var isLightFinish: Bool {
        [.silver, .skyBlue, .lightGold, .lavender, .pink].contains(self)
    }
}
