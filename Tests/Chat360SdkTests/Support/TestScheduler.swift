import Foundation
@testable import Chat360SDK

/// A virtual-time `Scheduler` for deterministic tests, mirroring `kotlinx-coroutines-test`'s
/// `TestCoroutineScheduler`/`advanceTimeBy`: nothing fires until `advance(by:)` is called, and
/// blocks scheduled *during* an advance (e.g. `HeartbeatManager` re-arming its own next ping) can
/// still fire within that same advance if their new due time falls inside the advanced window.
final class TestScheduler: Scheduler {
    private final class Entry {
        let id: Int
        let fireTime: TimeInterval
        let block: () -> Void
        var cancelled = false
        init(id: Int, fireTime: TimeInterval, block: @escaping () -> Void) {
            self.id = id
            self.fireTime = fireTime
            self.block = block
        }
    }

    private final class TestCancellable: Cancellable {
        let entry: Entry
        init(entry: Entry) { self.entry = entry }
        func cancel() { entry.cancelled = true }
    }

    private var now: TimeInterval = 0
    private var nextId = 0
    private var entries: [Entry] = []

    @discardableResult
    func schedule(after delay: TimeInterval, _ block: @escaping () -> Void) -> Cancellable {
        let entry = Entry(id: nextId, fireTime: now + delay, block: block)
        nextId += 1
        entries.append(entry)
        return TestCancellable(entry: entry)
    }

    /// Advances virtual time by `interval` seconds, firing every due, non-cancelled block in
    /// fire-time order (including ones scheduled by a block that just fired).
    func advance(by interval: TimeInterval) {
        let target = now + interval
        while true {
            entries.removeAll { $0.cancelled }
            guard let next = entries.filter({ $0.fireTime <= target }).min(by: { $0.fireTime < $1.fireTime }) else {
                break
            }
            entries.removeAll { $0 === next }
            now = next.fireTime
            if !next.cancelled {
                next.block()
            }
        }
        now = target
    }
}
