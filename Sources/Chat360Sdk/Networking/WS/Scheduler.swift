import Foundation

/// A cancellable handle to a scheduled block, returned by `Scheduler.schedule(after:_:)`.
protocol Cancellable {
    func cancel()
}

/// Abstracts "run this block after N seconds" so `AckTracker`/`HeartbeatManager`/`ReconnectManager`
/// can be driven by a real clock in production and a virtual clock in tests.
protocol Scheduler {
    @discardableResult
    func schedule(after delay: TimeInterval, _ block: @escaping () -> Void) -> Cancellable
}

/// Production scheduler backed by a `DispatchQueue`.
final class DispatchScheduler: Scheduler {
    private let queue: DispatchQueue

    init(queue: DispatchQueue = .main) {
        self.queue = queue
    }

    @discardableResult
    func schedule(after delay: TimeInterval, _ block: @escaping () -> Void) -> Cancellable {
        let item = DispatchWorkItem(block: block)
        queue.asyncAfter(deadline: .now() + delay, execute: item)
        return DispatchCancellable(item: item)
    }
}

private final class DispatchCancellable: Cancellable {
    private let item: DispatchWorkItem
    init(item: DispatchWorkItem) { self.item = item }
    func cancel() { item.cancel() }
}
