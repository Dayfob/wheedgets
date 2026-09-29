import Observation

/// Shared, observable view of the Accessibility grant, so every module and
/// the UI agree on it and only one waiter polls the system.
@MainActor
@Observable
final class AccessibilityStatus {
    private(set) var isTrusted = AccessibilityPermission.isTrusted

    @ObservationIgnored private var waiters: [String: (Bool) -> Void] = [:]
    @ObservationIgnored private var pollTask: Task<Void, Never>?

    func refresh() {
        isTrusted = AccessibilityPermission.isTrusted
    }

    /// Shows the system prompt and opens System Settings at the right pane.
    func request() {
        AccessibilityPermission.requestPrompt()
        AccessibilityPermission.openSystemSettings()
    }

    /// Prompts for access, then calls `completion(true)` once it is given, or
    /// `completion(false)` after three minutes without it. A later call with
    /// the same owner replaces the earlier one.
    func waitForGrant(owner: String, completion: @escaping (Bool) -> Void) {
        waiters[owner] = completion
        // Prompt once per wait: prompting resets a stale entry, which would
        // undo a grant the user is in the middle of giving.
        guard pollTask == nil else { return }
        AccessibilityPermission.requestPrompt()
        pollTask = Task { [weak self] in
            for _ in 0..<180 {
                try? await Task.sleep(for: .seconds(1))
                guard let self, !Task.isCancelled else { return }
                self.refresh()
                if self.isTrusted {
                    let ready = self.waiters.values
                    self.waiters.removeAll()
                    self.pollTask = nil
                    ready.forEach { $0(true) }
                    return
                }
            }
            let expired = self?.waiters.values
            self?.waiters.removeAll()
            self?.pollTask = nil
            expired?.forEach { $0(false) }
        }
    }

    func cancelWait(owner: String) {
        waiters[owner] = nil
    }
}
