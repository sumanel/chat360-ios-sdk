import Foundation

public final class AckTracker {
    private let scheduler: Chat360Scheduler
    private let retryDelaysMs: [Int64]
    private let onTimeout: (String) -> Void
    // Touched from four threads at once: the main thread (`trackSend`, on every send/retry), the
    // scheduler's queue (each timer callback re-arms itself), the socket's delegate queue
    // (`acknowledge`, when an ack frame arrives) and the session pool (`cancelAll`, on a room
    // switch). An unguarded Swift Dictionary crashes when two of them mutate it together, so every
    // access goes through `lock`. The `resend`/`onTimeout` callbacks always run outside it.
    private let lock = NSLock()
    private var timers: [String: Chat360CancellableTimer] = [:]

    public init(
        scheduler: Chat360Scheduler,
        retryDelaysMs: [Int64] = [15_000, 20_000, 30_000, 40_000, 30_000],
        onTimeout: @escaping (String) -> Void
    ) {
        self.scheduler = scheduler
        self.retryDelaysMs = retryDelaysMs
        self.onTimeout = onTimeout
    }

    public func trackSend(chatMsgId: String, resend: @escaping () -> Void) {
        scheduleAttempt(chatMsgId: chatMsgId, attempt: 0, resend: resend)
    }

    // Scheduling and storing happen under one lock hold: the scheduler never runs the action
    // inline, and the action needs the lock, so it can't observe (or overwrite) the dictionary
    // before its own timer has been stored.
    private func scheduleAttempt(chatMsgId: String, attempt: Int, resend: @escaping () -> Void) {
        lock.lock()
        defer { lock.unlock() }
        timers[chatMsgId]?.cancel()
        timers[chatMsgId] = scheduler.schedule(afterMs: retryDelaysMs[attempt]) { [weak self] in
            guard let self, self.isTracked(chatMsgId) else { return }
            resend()
            if attempt < self.retryDelaysMs.count - 1 {
                self.scheduleAttempt(chatMsgId: chatMsgId, attempt: attempt + 1, resend: resend)
            } else {
                self.armTimeout(chatMsgId: chatMsgId)
            }
        }
    }

    private func armTimeout(chatMsgId: String) {
        lock.lock()
        defer { lock.unlock() }
        // Acknowledged (or cancelled) while the last resend was going out - nothing left to time out.
        guard timers[chatMsgId] != nil else { return }
        timers[chatMsgId] = scheduler.schedule(afterMs: retryDelaysMs.last!) { [weak self] in
            guard let self, self.stopTracking(chatMsgId) else { return }
            self.onTimeout(chatMsgId)
        }
    }

    // A timer that was already running when `acknowledge`/`cancelAll` cancelled it still executes
    // (cancelling only stops timers that haven't started), so each callback re-checks it's still
    // wanted before resending, re-arming or reporting a timeout.
    private func isTracked(_ chatMsgId: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return timers[chatMsgId] != nil
    }

    private func stopTracking(_ chatMsgId: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return timers.removeValue(forKey: chatMsgId) != nil
    }

    public func acknowledge(chatMsgId: String?) {
        guard let chatMsgId else { return }
        lock.lock()
        let timer = timers.removeValue(forKey: chatMsgId)
        lock.unlock()
        timer?.cancel()
    }

    public func cancelAll() {
        lock.lock()
        let pending = Array(timers.values)
        timers.removeAll()
        lock.unlock()
        pending.forEach { $0.cancel() }
    }
}
