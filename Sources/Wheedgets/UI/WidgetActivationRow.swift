import SwiftUI
import WheedgetsCore

/// Top row of a widget's settings pane: is it the active widget, and a way
/// to switch to it without hunting through the menu.
struct WidgetActivationRow: View {
    let host: WidgetHost
    let kind: WidgetKind

    var body: some View {
        HStack {
            if isRunning {
                Label("On", systemImage: "circle.fill")
                    .foregroundStyle(.green)
                    .labelStyle(StatusLabelStyle())
                Spacer()
                Button("Turn Off") { host.turnOff() }
            } else {
                Label(isSelected ? "Off" : "Not active", systemImage: "circle")
                    .foregroundStyle(.secondary)
                    .labelStyle(StatusLabelStyle())
                Spacer()
                Button("Turn On") { host.switchTo(kind) }
            }
        }
    }

    private var isSelected: Bool { host.settings.selected == kind }
    private var isRunning: Bool { isSelected && host.state == .on }
}

private struct StatusLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon.font(.system(size: 8))
            configuration.title.foregroundStyle(.primary)
        }
    }
}
