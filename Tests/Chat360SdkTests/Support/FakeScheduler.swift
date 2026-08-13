import Foundation
@testable import Chat360SDK

final class FakeTimer: Chat360CancellableTimer {
    var isCancelled = false
    func cancel() { isCancelled = true }
}

final class FakeScheduler: Chat360Scheduler {
    private(set) var scheduled: [(delayMs: Int64, action: () -> Void, timer: FakeTimer)] = []

    func schedule(afterMs delayMs: Int64, _ action: @escaping () -> Void) -> Chat360CancellableTimer {
        let timer = FakeTimer()
        scheduled.append((delayMs, action, timer))
        return timer
    }

    func fireNext() {
        guard !scheduled.isEmpty else { return }
        let entry = scheduled.removeFirst()
        if !entry.timer.isCancelled { entry.action() }
    }

    func fireAll() {
        while !scheduled.isEmpty { fireNext() }
    }
}
