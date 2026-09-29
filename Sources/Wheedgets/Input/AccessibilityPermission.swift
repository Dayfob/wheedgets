import AppKit
import ApplicationServices
import OSLog

@MainActor
enum AccessibilityPermission {
    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Shows the system prompt that adds the app to the Accessibility list.
    ///
    /// If an entry for Wheedgets already exists but does not match this build's
    /// code signature (typical after rebuilding), System Settings shows it as
    /// enabled while `AXIsProcessTrusted()` stays false, and the prompt never
    /// appears. Clearing our own stale entry first makes the prompt register
    /// the current build. When access is missing anyway, there is nothing to lose.
    static func requestPrompt() {
        guard !isTrusted else { return }
        resetOwnEntry()
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    static func openSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }

    /// Removes only this app's Accessibility entry; other apps are untouched.
    private static func resetOwnEntry() {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        process.arguments = ["reset", "Accessibility", bundleID]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            Logger.input.error("tccutil reset failed: \(error.localizedDescription)")
        }
    }
}
