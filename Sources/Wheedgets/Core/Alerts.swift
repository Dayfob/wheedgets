import AppKit

@MainActor
enum Alerts {
    static func show(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        NSApp.activate()
        alert.runModal()
    }

    /// The list shows Wheedgets as allowed, yet the tap is refused: the grant
    /// belongs to a build with a different code signature.
    static func stalePermission() {
        show(
            title: String(localized: "Accessibility Access Needs a Refresh"),
            message: String(localized: "macOS still has access recorded for an older build of Wheedgets. In System Settings → Privacy & Security → Accessibility, remove Wheedgets with the “−” button, then turn the widget on again.")
        )
        AccessibilityPermission.openSystemSettings()
    }
}
