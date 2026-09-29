import OSLog
import ServiceManagement

@MainActor
enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            Logger.app.error("Launch at login change failed: \(error.localizedDescription)")
            Alerts.show(title: String(localized: "Couldn't Change Launch at Login"), message: error.localizedDescription)
        }
    }
}
