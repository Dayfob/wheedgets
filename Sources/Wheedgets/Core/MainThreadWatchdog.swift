import Foundation
import OSLog

/// Logs whenever the main thread stops answering for a noticeable time, so a
/// sluggish shortcut or slider can be traced to what blocked it.
/// View with: log stream --predicate 'subsystem == "dev.wheedgets.Wheedgets"'
final class MainThreadWatchdog: @unchecked Sendable {
    private let queue = DispatchQueue(label: "Wheedgets.MainThreadWatchdog", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var pingSent: DispatchTime?
    private static let threshold: UInt64 = 200_000_000 // 0.2 s

    func start() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(100))
        timer.setEventHandler { [weak self] in self?.tick() }
        timer.resume()
        self.timer = timer
    }

    /// Runs on `queue`: one ping in flight at a time; a late answer is a stall.
    private func tick() {
        guard pingSent == nil else { return }
        let sent = DispatchTime.now()
        pingSent = sent
        DispatchQueue.main.async { [self] in
            let delay = DispatchTime.now().uptimeNanoseconds - sent.uptimeNanoseconds
            if delay > Self.threshold {
                Logger.app.notice("Main thread stalled for \(delay / 1_000_000, privacy: .public) ms")
            }
            queue.async { self.pingSent = nil }
        }
    }
}
