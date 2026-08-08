import Foundation

/// Per-message delivery tracking. The underlying `URLSessionWebSocketTask` already queues writes
/// made before the handshake completes, so there is nothing to buffer here - only ack-timeout
/// tracking applies.
final class AckTracker {
    private let scheduler: Scheduler
    private let ackTimeout: TimeInterval
    private let onTimeout: (String) -> Void
    private var timers: [String: Cancellable] = [:]

    init(scheduler: Scheduler, ackTimeout: TimeInterval = 10, onTimeout: @escaping (String) -> Void) {
        self.scheduler = scheduler
        self.ackTimeout = ackTimeout
        self.onTimeout = onTimeout
    }

    func trackSend(_ chatMsgId: String) {
        timers[chatMsgId]?.cancel()
        timers[chatMsgId] = scheduler.schedule(after: ackTimeout) { [weak self] in
            self?.timers.removeValue(forKey: chatMsgId)
            self?.onTimeout(chatMsgId)
        }
    }

    func acknowledge(_ chatMsgId: String?) {
        guard let chatMsgId else { return }
        timers.removeValue(forKey: chatMsgId)?.cancel()
    }

    func cancelAll() {
        timers.values.forEach { $0.cancel() }
        timers.removeAll()
    }
}
