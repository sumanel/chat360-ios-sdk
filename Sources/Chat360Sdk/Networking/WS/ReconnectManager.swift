import Foundation

/// Mirrors the widget's reconnect logic: delay = baseDelay * intervalCount, doubling intervalCount
/// after each scheduled attempt and resetting to 1 on a successful open. Pure state - no socket
/// reference - so it's unit-testable with a virtual-time scheduler.
final class ReconnectManager {
    private let scheduler: Scheduler
    private let baseDelay: TimeInterval
    private let reconnect: () -> Void

    private var intervalCount = 1
    private var timer: Cancellable?

    init(scheduler: Scheduler, baseDelay: TimeInterval = 5, reconnect: @escaping () -> Void) {
        self.scheduler = scheduler
        self.baseDelay = baseDelay
        self.reconnect = reconnect
    }

    func onConnected() {
        timer?.cancel()
        timer = nil
        intervalCount = 1
    }

    /// `suppress` covers both "flow finished"/"chatbox hidden" and the superseded-session signal.
    func scheduleReconnect(suppress: Bool) {
        guard !suppress else { return }
        let delay = baseDelay * Double(intervalCount)
        intervalCount *= 2
        timer = scheduler.schedule(after: delay) { [weak self] in
            self?.reconnect()
        }
    }

    func cancel() {
        timer?.cancel()
        timer = nil
    }
}
