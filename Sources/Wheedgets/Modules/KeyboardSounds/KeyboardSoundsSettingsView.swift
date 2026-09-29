import SwiftUI
import WheedgetsCore

struct KeyboardSoundsSettingsView: View {
    @Bindable var sounds: KeyboardSounds
    let host: WidgetHost
    @State private var tryItText = ""

    var body: some View {
        Form {
            Section {
                WidgetActivationRow(host: host, kind: .keyboardSounds)
                statusRow
            } footer: {
                Text("Wheedgets only notes which key moved to pick its sound. What you type is never stored or sent anywhere. Password fields stay silent.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("Pack", selection: $sounds.settings.pack) {
                    Section("Built-in") {
                        Text("Clicky").tag(KeyPackID.builtin(.clicky))
                        Text("Thocky").tag(KeyPackID.builtin(.thocky))
                    }
                    if !sounds.installedPacks.isEmpty {
                        Section("Imported") {
                            ForEach(sounds.installedPacks) { pack in
                                Text(pack.name).tag(pack.id)
                            }
                        }
                    }
                }
                ForEach(sounds.installedPacks) { pack in
                    HStack {
                        Text(pack.name)
                        Spacer()
                        Button(role: .destructive) {
                            sounds.removePack(pack)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .help("Remove pack")
                    }
                }
                HStack {
                    Button("Import Mechvibes Pack…", systemImage: "square.and.arrow.down") { sounds.importPack() }
                    Spacer()
                    Button("Show in Finder") { sounds.revealPacksInFinder() }
                }
            } header: {
                Text("Sound Pack")
            } footer: {
                Text("Wheedgets plays sound packs made for Mechvibes. Choose the pack's folder (the one with config.json) or its .zip file.")
                    .foregroundStyle(.secondary)
            }

            Section("Sound") {
                LabeledContent("Volume") {
                    VolumeSlider(value: $sounds.settings.volume)
                        .frame(width: 260)
                }
                Toggle("Play key release sounds", isOn: $sounds.settings.playsReleaseSounds)
                HStack {
                    TextField("Try it", text: $tryItText, prompt: Text("Type here to hear the pack"))
                    Button("Preview", systemImage: "play.fill") { sounds.preview() }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .help("Preview")
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Keyboard Sounds")
    }

    @ViewBuilder
    private var statusRow: some View {
        switch sounds.packStatus {
        case .idle, .ready:
            EmptyView()
        case .loading:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Loading pack…").foregroundStyle(.secondary)
            }
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        }
    }
}
