import SwiftUI
import WheedgetsCore

/// Status, shortcut and on/off control at the top of widget panels.
struct WidgetHeader<Trailing: View>: View {
    let host: WidgetHost
    let openSettings: @MainActor () -> Void
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
                .shadow(color: statusColor, radius: host.state == .on ? 4 : 0)
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(host.settings.hotkey.displayName)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
            PanelIconButton(systemImage: "power", help: host.state == .off ? "Turn On" : "Turn Off") {
                host.toggle()
            }
            PanelIconButton(systemImage: "gearshape", help: "Settings") {
                openSettings()
            }
            trailing()
        }
        .foregroundStyle(.primary)
    }

    private var title: String {
        switch host.state {
        case .waitingForPermission: String(localized: "Waiting for access…")
        case .on, .off: host.settings.selected.displayName
        }
    }

    private var statusColor: Color {
        switch host.state {
        case .on: .green
        case .off: .gray
        case .waitingForPermission: .orange
        }
    }
}
