import SwiftUI
import WheedgetsCore

/// Settings with a sidebar: General, then one pane per widget.
struct SettingsView: View {
    enum Pane: Hashable {
        case general
        case widget(WidgetKind)
    }

    let host: WidgetHost
    let audio: AudioEngine
    let drums: DrumKit
    let spinner: Spinner
    let keyboardSounds: KeyboardSounds

    @State private var selection: Pane? = .general

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Label("General", systemImage: "gearshape").tag(Pane.general)
                Section("Widgets") {
                    ForEach(WidgetKind.allCases) { kind in
                        Label(kind.displayName, systemImage: kind.systemImage).tag(Pane.widget(kind))
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 240)
        } detail: {
            switch selection ?? .general {
            case .general:
                GeneralSettingsView(host: host, audio: audio)
            case .widget(.drums):
                DrumSettingsView(drums: drums, host: host)
            case .widget(.spinner):
                SpinnerSettingsView(spinner: spinner, host: host)
            case .widget(.keyboardSounds):
                KeyboardSoundsSettingsView(sounds: keyboardSounds, host: host)
            }
        }
        .frame(minWidth: 760, minHeight: 520)
        .task {
            // Picks up a grant made in System Settings while this window is open.
            while !Task.isCancelled {
                host.accessibility.refresh()
                try? await Task.sleep(for: .seconds(1.5))
            }
        }
    }
}

struct GeneralSettingsView: View {
    @Bindable var host: WidgetHost
    @Bindable var audio: AudioEngine
    @State private var launchesAtLogin = LaunchAtLogin.isEnabled

    var body: some View {
        Form {
            Section {
                LabeledContent("On/off shortcut") {
                    KeyRecorderButton(title: host.settings.hotkey.displayName, mode: .shortcut, host: host) { keyCode, modifiers in
                        host.settings.hotkey = Hotkey(keyCode: keyCode, modifiers: modifiers)
                    }
                }
                if !host.hotkeyAvailable {
                    Label("This shortcut is taken by another app. Choose a different one.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            } header: {
                Text("Widgets")
            } footer: {
                Text("One widget is active at a time: pick it in the menu bar. The shortcut turns it on and off. Shortcuts with ⌘, ⌃ or ⌥ always keep working.")
                    .foregroundStyle(.secondary)
            }

            Section("Sound") {
                LabeledContent("Master volume") {
                    VolumeSlider(value: $audio.masterVolume, range: Volume.master)
                        .frame(width: 260)
                }
            }

            Section("Permission") {
                if host.accessibility.isTrusted {
                    Label("Accessibility access granted", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    HStack {
                        Label("Accessibility access is needed to capture keys", systemImage: "lock.fill")
                        Spacer()
                        Button("Open System Settings") { host.accessibility.request() }
                    }
                }
            }

            Section("App") {
                Toggle("Launch at login", isOn: Binding(
                    get: { launchesAtLogin },
                    set: {
                        LaunchAtLogin.setEnabled($0)
                        launchesAtLogin = LaunchAtLogin.isEnabled
                    }
                ))
            }
        }
        .formStyle(.grouped)
        .navigationTitle("General")
    }
}
