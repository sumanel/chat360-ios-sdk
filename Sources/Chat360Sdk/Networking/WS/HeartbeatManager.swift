import Foundation

public final class HeartbeatManager {
    private let scheduler: Chat360Scheduler
    private let pingWaitingTimerMs: Int64
    private let sendPing: () -> Void
    private let onSlowConnectionChanged: (Bool) -> Void
    private var sendTimer: Chat360CancellableTimer?
    private var waitTimer: Chat360CancellableTimer?
    private var isSlow = false

    public init(
        scheduler: Chat360Scheduler,
        pingWaitingTimerMs: Int64 = 2_000,
        sendPing: @escaping () -> Void,
        onSlowConnectionChanged: @escaping (Bool) -> Void
    ) {
        self.scheduler = scheduler
        self.pingWaitingTimerMs = pingWaitingTimerMs
        self.sendPing = sendPing
        self.onSlowConnectionChanged = onSlowConnectionChanged
    }

    public func start() {
        scheduleSendPing()
    }

    public func onMessageReceived(isPong: Bool) {
        if isPong {
            waitTimer?.cancel()
            waitTimer = nil
        }
        if isSlow {
            isSlow = false
            onSlowConnectionChanged(false)
        }
        scheduleSendPing()
    }

    public func stop() {
        sendTimer?.cancel()
        waitTimer?.cancel()
        sendTimer = nil
        waitTimer = nil
    }

    private func scheduleSendPing() {
        sendTimer?.cancel()
        sendTimer = scheduler.schedule(afterMs: pingWaitingTimerMs) { [weak self] in
            guard let self else { return }
            self.sendPing()
            self.waitTimer?.cancel()
            self.waitTimer = self.scheduler.schedule(afterMs: self.pingWaitingTimerMs) { [weak self] in
                guard let self else { return }
                self.isSlow = true
                self.onSlowConnectionChanged(true)
            }
        }
    }
}
