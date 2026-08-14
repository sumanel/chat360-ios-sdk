import Foundation

public final class ReconnectManager {
    private let scheduler: Chat360Scheduler
    private let baseDelayMs: Int64
    private let reconnect: () -> Void
    private var intervalCount = 1
    private var timer: Chat360CancellableTimer?

    public init(scheduler: Chat360Scheduler, baseDelayMs: Int64 = 5_000, reconnect: @escaping () -> Void) {
        self.scheduler = scheduler
        self.baseDelayMs = baseDelayMs
        self.reconnect = reconnect
    }

    public func onConnected() {
        timer?.cancel()
        timer = nil
        intervalCount = 1
    }

    public func scheduleReconnect(suppress: Bool) {
        if suppress {
            NSLog("[Chat360WS] Reconnect suppressed")
            return
        }
        let delayMs = baseDelayMs * Int64(intervalCount)
        intervalCount *= 2
        NSLog("[Chat360WS] Reconnect scheduled in %dms (nextBackoffMultiplier=%d)", delayMs, intervalCount)
        timer = scheduler.schedule(afterMs: delayMs) { [weak self] in
            NSLog("[Chat360WS] Reconnecting now")
            self?.reconnect()
        }
    }

    public func cancel() {
        timer?.cancel()
        timer = nil
    }
}
