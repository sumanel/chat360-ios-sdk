import Foundation

public final class HeartbeatManager {
    private let scheduler: Chat360Scheduler
    private let pingWaitingTimerMs: Int64
    private let sendPing: () -> Void
    private let onSlowConnectionChanged: (Bool) -> Void
    // start/stop/onMessageReceived arrive from the socket's delegate queue and the repository, and
    // the timers re-arm themselves on the scheduler's queue, so all of this is guarded by `lock`.
    // The sendPing / onSlowConnectionChanged callbacks always run outside it.
    private let lock = NSLock()
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
        lock.lock()
        if isPong {
            waitTimer?.cancel()
            waitTimer = nil
        }
        let wasSlow = isSlow
        isSlow = false
        lock.unlock()
        if wasSlow { onSlowConnectionChanged(false) }
        scheduleSendPing()
    }

    public func stop() {
        lock.lock()
        let timers = [sendTimer, waitTimer]
        sendTimer = nil
        waitTimer = nil
        lock.unlock()
        timers.forEach { $0?.cancel() }
    }

    // Scheduling and storing happen under one hold: the scheduler never runs the action inline, and
    // the action needs the lock, so it can't see (or overwrite) a timer before it has been stored.
    private func scheduleSendPing() {
        lock.lock()
        defer { lock.unlock() }
        sendTimer?.cancel()
        sendTimer = scheduler.schedule(afterMs: pingWaitingTimerMs) { [weak self] in
            guard let self else { return }
            self.sendPing()
            self.armWaitTimer()
        }
    }

    private func armWaitTimer() {
        lock.lock()
        defer { lock.unlock() }
        waitTimer?.cancel()
        waitTimer = scheduler.schedule(afterMs: pingWaitingTimerMs) { [weak self] in
            guard let self else { return }
            self.lock.lock()
            self.isSlow = true
            self.lock.unlock()
            self.onSlowConnectionChanged(true)
        }
    }
}
