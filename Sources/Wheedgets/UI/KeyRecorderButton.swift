import AppKit
import Carbon.HIToolbox
import WheedgetsCore
import SwiftUI

/// Click, then press a key. Used for pad keys and for the on/off shortcut.
struct KeyRecorderButton: View {
    enum Mode {
        /// A bare key; ⌘ ⌃ ⌥ are rejected because those combinations pass through.
        case padKey
        /// A combination that includes ⌘, ⌃ or ⌥.
        case shortcut
    }

    let title: String
    let mode: Mode
    let host: WidgetHost
    let onRecord: (UInt16, Modifiers) -> Void

    @State private var recorderID = UUID()
    @State private var monitor: Any?

    private var isRecording: Bool { host.activeRecorder == recorderID }

    var body: some View {
        Button {
            isRecording ? stop() : start()
        } label: {
            Text(isRecording ? promptTitle : title)
                .font(.system(.body, design: .rounded).weight(.medium))
                .frame(minWidth: 72)
        }
        .buttonStyle(.bordered)
        .tint(isRecording ? .accentColor : nil)
        .help(isRecording ? "Press Esc to cancel" : "Click to change")
        .onChange(of: host.activeRecorder) { _, active in
            // Another recorder took over: stop listening here.
            if active != recorderID { removeMonitor() }
        }
        .onDisappear { stop() }
    }

    private var promptTitle: String {
        mode == .padKey ? String(localized: "Press a key…") : String(localized: "Press shortcut…")
    }

    private func start() {
        host.activeRecorder = recorderID
        removeMonitor()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let keyCode = event.keyCode
            let modifiers = Modifiers(event.modifierFlags)
            MainActor.assumeIsolated { record(keyCode: keyCode, modifiers: modifiers) }
            return nil
        }
    }

    private func record(keyCode: UInt16, modifiers: Modifiers) {
        if keyCode == UInt16(kVK_Escape) && !modifiers.isValidForShortcut {
            stop()
            return
        }
        let accepted = switch mode {
        case .padKey: !modifiers.isValidForShortcut && keyCode != KeyCodes.escape
        case .shortcut: modifiers.isValidForShortcut
        }
        guard accepted else {
            NSSound.beep()
            return
        }
        onRecord(keyCode, mode == .padKey ? [] : modifiers)
        stop()
    }

    private func stop() {
        removeMonitor()
        if host.activeRecorder == recorderID { host.activeRecorder = nil }
    }

    private func removeMonitor() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
