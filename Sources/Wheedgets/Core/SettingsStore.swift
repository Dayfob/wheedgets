import Foundation
import OSLog
import WheedgetsCore

/// Persists `AppSettings` as one versioned JSON value in UserDefaults.
///
/// Modules own their slice of the settings; the store only knows how to
/// gather them (`snapshot`) and writes debounced, so dragging a slider does
/// not hit the disk 60 times a second.
@MainActor
final class SettingsStore {
    private let key = "settings.v1"
    private let defaults = UserDefaults.standard
    private var saveTask: Task<Void, Never>?

    var snapshot: () -> AppSettings = { AppSettings() }

    func load() -> AppSettings {
        guard let data = defaults.data(forKey: key) else { return AppSettings() }
        do {
            return try JSONDecoder().decode(AppSettings.self, from: data)
        } catch {
            Logger.app.error("Settings unreadable, using defaults: \(error.localizedDescription)")
            return AppSettings()
        }
    }

    func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard let self, !Task.isCancelled else { return }
            self.saveNow()
        }
    }

    func saveNow() {
        saveTask?.cancel()
        do {
            defaults.set(try JSONEncoder().encode(snapshot()), forKey: key)
        } catch {
            Logger.app.error("Settings could not be saved: \(error.localizedDescription)")
        }
    }
}

/// Re-runs `apply` whenever an observable value it read changes.
@MainActor
func observeChanges(_ apply: @escaping @MainActor () -> Void) {
    withObservationTracking(apply) {
        Task { @MainActor in observeChanges(apply) }
    }
}
