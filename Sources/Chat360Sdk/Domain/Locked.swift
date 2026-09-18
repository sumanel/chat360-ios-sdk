import Foundation

/// Makes every read and write of a property atomic.
///
/// `ChatRepository`'s socket and session state is touched from several threads at once: the main
/// thread (sends, retries), the socket's delegate queue (incoming frames, open/close), the
/// repository's timer queue (reconnect, heartbeat, ack retries) and the Swift concurrency pool
/// (`connect` / `establishSession`). An unsynchronised Swift value crashes - or is silently
/// corrupted - when two threads touch it together. This only guards each single access; a
/// check-then-act sequence still needs `ChatRepository.stateLock` around the whole sequence.
@propertyWrapper
final class Locked<Value> {
    private let lock = NSLock()
    private var value: Value

    init(wrappedValue: Value) {
        value = wrappedValue
    }

    var wrappedValue: Value {
        get {
            lock.lock()
            defer { lock.unlock() }
            return value
        }
        set {
            lock.lock()
            value = newValue
            lock.unlock()
        }
    }

    /// Atomic read-modify-write, e.g. `_counter.mutate { $0 += 1; return $0 }`.
    @discardableResult
    func mutate<Result>(_ body: (inout Value) -> Result) -> Result {
        lock.lock()
        defer { lock.unlock() }
        return body(&value)
    }
}
