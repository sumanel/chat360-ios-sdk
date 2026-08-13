import Foundation

public protocol Chat360CancellableTimer {
    func cancel()
}

public protocol Chat360Scheduler {
    func schedule(afterMs delayMs: Int64, _ action: @escaping () -> Void) -> Chat360CancellableTimer
}

public final class DispatchQueueScheduler: Chat360Scheduler {
    private let queue: DispatchQueue

    public init(queue: DispatchQueue = .main) {
        self.queue = queue
    }

    public func schedule(afterMs delayMs: Int64, _ action: @escaping () -> Void) -> Chat360CancellableTimer {
        let workItem = DispatchWorkItem(block: action)
        queue.asyncAfter(deadline: .now() + .milliseconds(Int(delayMs)), execute: workItem)
        return DispatchWorkItemTimer(workItem: workItem)
    }
}

private final class DispatchWorkItemTimer: Chat360CancellableTimer {
    private let workItem: DispatchWorkItem

    init(workItem: DispatchWorkItem) {
        self.workItem = workItem
    }

    func cancel() {
        workItem.cancel()
    }
}
