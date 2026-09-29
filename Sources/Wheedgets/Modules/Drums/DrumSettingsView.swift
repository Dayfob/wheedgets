import SwiftUI
import WheedgetsCore

struct DrumSettingsView: View {
    @Bindable var drums: DrumKit
    let host: WidgetHost

    var body: some View {
        Form {
            Section {
                WidgetActivationRow(host: host, kind: .drums)
            }

            Section {
                Picker("Play with", selection: $drums.settings.control) {
                    Text("Keyboard").tag(DrumControl.keyboard)
                    Text("Trackpad").tag(DrumControl.trackpad)
                }
                .pickerStyle(.segmented)
                Toggle("Show the pads while drums are on", isOn: $drums.settings.showsPanel)
                LabeledContent("Volume") {
                    VolumeSlider(value: $drums.settings.volume)
                        .frame(width: 260)
                }
            } footer: {
                Text("Custom sounds can be WAV, AIFF, MP3, M4A or CAF, up to 10 seconds.")
                    .foregroundStyle(.secondary)
            }

            switch drums.settings.control {
            case .keyboard:
                keyboardSections
            case .trackpad:
                trackpadSection
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Drums")
    }

    @ViewBuilder
    private var keyboardSections: some View {
        Section {
            Picker("Bound keys", selection: $drums.settings.keyHandling) {
                Text("Only play drums").tag(KeyHandling.capture)
                Text("Play drums and type").tag(KeyHandling.passThrough)
            }
            .pickerStyle(.radioGroup)
        } footer: {
            Text(drums.settings.keyHandling == .capture
                 ? "Bound keys never reach the app you're typing in. Esc turns the drums off."
                 : "Bound keys play a drum and still type as usual. Turn the drums off with the shortcut.")
                .foregroundStyle(.secondary)
        }

        Section {
            ForEach(drums.settings.pads) { pad in
                PadRow(drums: drums, host: host, pad: pad)
            }
            HStack {
                Button("Add Pad", systemImage: "plus") { drums.addPad() }
                Spacer()
                Button("Restore Default Kit") { drums.restoreDefaultKit() }
            }
        } header: {
            Text("Pads")
        } footer: {
            Text("Keys are physical positions, so bindings work with any keyboard layout.")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var trackpadSection: some View {
        let grid = drums.settings.trackpad
        Section {
            if !drums.trackpadAvailable {
                Label("This version of macOS doesn't give access to trackpad fingers.", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
            Picker("Hit with", selection: $drums.settings.trackpad.trigger) {
                Text("Taps").tag(DrumTrigger.tap)
                Text("Clicks").tag(DrumTrigger.click)
            }
            .pickerStyle(.segmented)
            Toggle("Harder hits play louder", isOn: $drums.settings.trackpad.velocitySensitive)
            Picker("Zones", selection: $drums.settings.trackpad.layout) {
                Text("Grid").tag(DrumZoneLayout.grid)
                Text("Drawn").tag(DrumZoneLayout.custom)
            }
            .pickerStyle(.segmented)
        } header: {
            Text("Trackpad")
        } footer: {
            Text(grid.trigger == .tap
                 ? "Every touch plays the zone under the finger, so moving the pointer drums too. Clicks and the pointer keep working as usual."
                 : "Clicking the trackpad plays the zone under the finger; moving the pointer stays silent. Clicks still reach the app underneath.")
                .foregroundStyle(.secondary)
        }

        switch grid.layout {
        case .grid: gridSection
        case .custom: customZonesSection
        }
    }

    @ViewBuilder
    private var gridSection: some View {
        let grid = drums.settings.trackpad
        Section {
            LabeledContent("Size") {
                HStack(spacing: 16) {
                    Stepper(value: Binding(
                        get: { grid.rows },
                        set: { drums.resizeTrackpadGrid(rows: $0, columns: grid.columns) }
                    ), in: DrumTrackpadSettings.sizeRange) {
                        Text("Rows: \(grid.rows)")
                    }
                    Stepper(value: Binding(
                        get: { grid.columns },
                        set: { drums.resizeTrackpadGrid(rows: grid.rows, columns: $0) }
                    ), in: DrumTrackpadSettings.sizeRange) {
                        Text("Columns: \(grid.columns)")
                    }
                }
            }
            VStack(spacing: 6) {
                ForEach(0..<grid.rows, id: \.self) { row in
                    HStack(spacing: 6) {
                        ForEach(0..<grid.columns, id: \.self) { column in
                            SoundMenu(
                                source: grid.zone(row: row, column: column),
                                onSelect: { drums.setZone(row: row, column: column, to: $0) },
                                onChooseFile: { drums.chooseSample(forZoneRow: row, column: column) }
                            )
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(grid.zone(row: row, column: column).tint.opacity(0.18),
                                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                    }
                }
            }
            .aspectRatio(1.6, contentMode: .fit)
        } footer: {
            Text("Give several zones the same sound to make it a bigger target.")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var customZonesSection: some View {
        let zones = drums.settings.trackpad.customZones
        let draft: [ZonePoint] = if case .drawing(let points) = drums.tracing { points } else { [] }
        Section {
            CustomZonesView(
                zones: zones,
                selected: drums.selectedCustomZone,
                draft: draft,
                onTap: { id in
                    drums.selectedCustomZone = id
                    drums.playCustomZone(id)
                }
            )
            HStack {
                switch drums.tracing {
                case .drawing:
                    Label("Trace the zone on the trackpad with one finger, then lift it.", systemImage: "hand.draw")
                        .foregroundStyle(Color.accentColor)
                    Spacer()
                    Button("Cancel") { drums.cancelTracing() }
                case .idle, .rejected:
                    Button("Draw Zone", systemImage: "hand.draw") { drums.startTracing() }
                        .disabled(!drums.trackpadAvailable)
                    if drums.tracing == .rejected {
                        Text("Too small — draw a bigger outline.")
                            .foregroundStyle(.orange)
                    }
                    Spacer()
                    if !zones.isEmpty {
                        Button("Remove All", role: .destructive) { drums.removeAllCustomZones() }
                    }
                }
            }
            ForEach(Array(zones.enumerated()), id: \.element.id) { number, zone in
                HStack(spacing: 10) {
                    Circle()
                        .fill(zone.sound.tint)
                        .frame(width: 10, height: 10)
                    Text(verbatim: "\(number + 1)")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    SoundMenu(
                        source: zone.sound,
                        onSelect: { drums.setCustomZoneSound(zone.id, to: $0) },
                        onChooseFile: { drums.chooseSample(forCustomZone: zone.id) }
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Button {
                        drums.playCustomZone(zone.id)
                    } label: {
                        Image(systemName: "play.fill")
                    }
                    .buttonStyle(.borderless)
                    .help("Preview")
                    Button(role: .destructive) {
                        drums.removeCustomZone(zone.id)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .help("Remove zone")
                }
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(zone.id == drums.selectedCustomZone ? Color.accentColor.opacity(0.12) : .clear)
                )
                .contentShape(Rectangle())
                .onTapGesture { drums.selectedCustomZone = zone.id }
            }
        } footer: {
            Text("Draw zones of any shape by tracing them on the trackpad. Where zones overlap, the one drawn later wins; outside every zone the trackpad stays silent.")
                .foregroundStyle(.secondary)
        }
    }
}

/// Picks a drum sound: the built-in kit or a file.
struct SoundMenu: View {
    let source: SoundSource
    let onSelect: (SoundSource) -> Void
    let onChooseFile: () -> Void

    var body: some View {
        Menu {
            Section("Built-in") {
                ForEach(DrumSound.allCases) { sound in
                    Button(sound.displayName) { onSelect(.builtin(sound)) }
                }
            }
            Divider()
            Button("Choose Sound File…", action: onChooseFile)
        } label: {
            Text(source.displayName)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

private struct PadRow: View {
    let drums: DrumKit
    let host: WidgetHost
    let pad: Pad

    var body: some View {
        HStack(spacing: 12) {
            KeyRecorderButton(title: KeyNames.name(for: pad.keyCode), mode: .padKey, host: host) { keyCode, _ in
                drums.settings.assignKey(keyCode, toPad: pad.id)
            }
            .frame(width: 96)

            soundMenu

            Image(systemName: "speaker.fill")
                .foregroundStyle(.secondary)
                .font(.caption)
            Slider(value: Binding(
                get: { pad.gain },
                set: { gain in drums.updatePad(pad.id) { $0.gain = gain } }
            ), in: 0...1)
            .frame(width: 110)
            .help("Pad volume")

            Button {
                drums.trigger(pad)
            } label: {
                Image(systemName: "play.fill")
            }
            .buttonStyle(.borderless)
            .help("Preview")

            Button(role: .destructive) {
                drums.removePad(pad.id)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Remove pad")
        }
    }

    private var soundMenu: some View {
        SoundMenu(
            source: pad.source,
            onSelect: { drums.setSound($0, forPad: pad.id) },
            onChooseFile: { drums.chooseSample(forPad: pad.id) }
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
