import Foundation

public final class AckTracker {
    private let scheduler: Chat360Scheduler
    private let retryDelaysMs: [Int64]
    private let onTimeout: (String) -> Void
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

    private func scheduleAttempt(chatMsgId: String, attempt: Int, resend: @escaping () -> Void) {
        timers[chatMsgId]?.cancel()
        timers[chatMsgId] = scheduler.schedule(afterMs: retryDelaysMs[attempt]) { [weak self] in
            guard let self else { return }
            resend()
            if attempt < self.retryDelaysMs.count - 1 {
                self.scheduleAttempt(chatMsgId: chatMsgId, attempt: attempt + 1, resend: resend)
            } else {
                self.timers[chatMsgId] = self.scheduler.schedule(afterMs: self.retryDelaysMs.last!) { [weak self] in
                    guard let self else { return }
                    self.timers.removeValue(forKey: chatMsgId)
                    self.onTimeout(chatMsgId)
                }
            }
        }
    }

    public func acknowledge(chatMsgId: String?) {
        guard let chatMsgId else { return }
        timers.removeValue(forKey: chatMsgId)?.cancel()
    }

    public func cancelAll() {
        timers.values.forEach { $0.cancel() }
        timers.removeAll()
    }
}
