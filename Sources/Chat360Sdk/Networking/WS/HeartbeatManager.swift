import Foundation

/// The ping/pong cycle: `pingWaitingTimer` (2s) is used as both the idle-before-ping delay AND
/// the wait-for-pong delay. Any incoming frame (not just a pong) reschedules the next ping - only
/// a pong cancels the currently-pending "waiting for pong" timer.
final class HeartbeatManager {
    private let scheduler: Scheduler
    private let pingWaitingTimer: TimeInterval
    private let sendPing: () -> Void
    private let onSlowConnectionChanged: (Bool) -> Void

    private var sendTimer: Cancellable?
    private var waitTimer: Cancellable?
    private var isSlow = false

    init(
        scheduler: Scheduler,
        pingWaitingTimer: TimeInterval = 2,
        sendPing: @escaping () -> Void,
        onSlowConnectionChanged: @escaping (Bool) -> Void
    ) {
        self.scheduler = scheduler
        self.pingWaitingTimer = pingWaitingTimer
        self.sendPing = sendPing
        self.onSlowConnectionChanged = onSlowConnectionChanged
    }

    func start() {
        scheduleSendPing()
    }

    /// Call for every inbound frame, pong or not.
    func onMessageReceived(isPong: Bool) {
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

    func stop() {
        sendTimer?.cancel()
        waitTimer?.cancel()
        sendTimer = nil
        waitTimer = nil
    }

    private func scheduleSendPing() {
        sendTimer?.cancel()
        sendTimer = scheduler.schedule(after: pingWaitingTimer) { [weak self] in
            guard let self else { return }
            self.sendPing()
            self.waitTimer?.cancel()
            self.waitTimer = self.scheduler.schedule(after: self.pingWaitingTimer) { [weak self] in
                self?.isSlow = true
                self?.onSlowConnectionChanged(true)
            }
        }
    }
}
