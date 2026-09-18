import Foundation

@available(iOS 13.0, *)
public final class Chat360WebSocketClient: NSObject {
    private struct Callbacks {
        let onOpen: () -> Void
        let onMessage: (String) -> Void
        let onClosed: (Int, String) -> Void
        let onFailure: (Error) -> Void
    }

    private let configuration: URLSessionConfiguration
    private lazy var session: URLSession = URLSession(
        configuration: configuration,
        delegate: self,
        delegateQueue: nil
    )
    // `task`, `callbacks` and `generation` are read and written from the caller's thread and from
    // URLSession's delegate queue (receive/send completions, open/close delegate calls), so every
    // access goes through `lock`. Callbacks are always invoked outside it.
    private let lock = NSLock()
    private(set) var task: URLSessionWebSocketTask?
    private var callbacks: Callbacks?

    /// Bumped on every connect()/close() so callbacks from a superseded
    /// connection (in-flight receive/send completions from an old task)
    /// are dropped instead of firing into the current connection's state.
    private var generation: Int = 0

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    public init(session: URLSession = URLSession(configuration: .default)) {
        self.configuration = session.configuration
        super.init()
    }

    public func connect(
        wsUrl: String,
        onOpen: @escaping () -> Void,
        onMessage: @escaping (String) -> Void,
        onClosed: @escaping (Int, String) -> Void,
        onFailure: @escaping (Error) -> Void
    ) {
        NSLog("[Chat360WS] Connecting -> %@", wsUrl)
        guard let url = URL(string: wsUrl) else {
            onFailure(URLError(.badURL))
            return
        }
        let request = URLRequest(url: url)
        let newTask = session.webSocketTask(with: request)
        let (previous, myGeneration): (URLSessionWebSocketTask?, Int) = locked {
            let previous = task
            generation += 1
            callbacks = Callbacks(onOpen: onOpen, onMessage: onMessage, onClosed: onClosed, onFailure: onFailure)
            task = newTask
            return (previous, generation)
        }
        // Never leave the previous socket running underneath the new one - its callbacks are
        // already ignored (generation), so an uncancelled one would just sit open, unseen.
        previous?.cancel(with: .goingAway, reason: "replaced".data(using: .utf8))
        newTask.resume()
        listen(generation: myGeneration)
    }

    public func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didOpenWithProtocol protocol: String?
    ) {
        guard let callbacks = locked({ task === webSocketTask ? self.callbacks : nil }) else { return }
        NSLog("[Chat360WS] Socket OPEN")
        callbacks.onOpen()
    }

    public func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {
        // Consume (clear) callbacks so the outstanding receive() in listen(),
        // which also completes with an error once the socket closes, can't
        // additionally fire onFailure for this same close event.
        guard let callbacks = locked({ () -> Callbacks? in
            guard task === webSocketTask, let current = self.callbacks else { return nil }
            self.callbacks = nil
            return current
        }) else { return }
        let reasonText = reason.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        NSLog("[Chat360WS] Socket CLOSED by server: %d %@", closeCode.rawValue, reasonText)
        callbacks.onClosed(closeCode.rawValue, reasonText)
    }

    private func listen(generation myGeneration: Int) {
        locked({ task })?.receive { [weak self] result in
            guard let self else { return }
            // A newer connect()/close() has superseded this one; let this
            // receive chain die instead of touching the current connection.
            guard let callbacks = self.locked({ myGeneration == self.generation ? self.callbacks : nil }) else { return }
            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    Chat360WebSocketClient.logFull("[Chat360WS] << RECEIVED", text)
                    callbacks.onMessage(text)
                case .data(let data):
                    let text = String(data: data, encoding: .utf8) ?? ""
                    Chat360WebSocketClient.logFull("[Chat360WS] << RECEIVED (data)", text)
                    callbacks.onMessage(text)
                @unknown default:
                    break
                }
                self.listen(generation: myGeneration)
            case .failure(let error):
                // Consumed here first if didCloseWith hasn't fired yet for this
                // close/failure; clearing prevents a subsequent didCloseWith
                // (or another in-flight receive) from double-notifying.
                self.locked { self.callbacks = nil }
                NSLog("[Chat360WS] Socket FAILURE: %@", error.localizedDescription)
                callbacks.onFailure(error)
            }
        }
    }

    @discardableResult
    public func send(_ text: String) -> Bool {
        let (currentTask, myGeneration) = locked { (task, generation) }
        guard let currentTask, currentTask.state == .running else {
            Chat360WebSocketClient.logFull("[Chat360WS] >> SEND FAILED (socket not open)", text)
            return false
        }
        currentTask.send(.string(text)) { [weak self] error in
            guard let self, let error else { return }
            guard let callbacks = self.locked({ myGeneration == self.generation ? self.callbacks : nil }) else { return }
            NSLog("[Chat360WS] >> SEND FAILED: %@", error.localizedDescription)
            callbacks.onFailure(error)
        }
        Chat360WebSocketClient.logFull("[Chat360WS] >> SENT", text)
        return true
    }

    public func close() {
        NSLog("[Chat360WS] Closing socket (client requested)")
        let (closedTask, closedCallbacks): (URLSessionWebSocketTask?, Callbacks?) = locked {
            generation += 1
            let result = (task, callbacks)
            task = nil
            callbacks = nil
            return result
        }
        closedTask?.cancel(with: .normalClosure, reason: "client closed".data(using: .utf8))
        closedCallbacks?.onClosed(1000, "client closed")
    }

    // NSLog (like os_log, which it's built on) silently truncates each %@ argument around 1024
    // bytes, which was cutting these payloads off mid-JSON - unusable for debugging a malformed
    // or unexpected bot response. Splitting into fixed-size chunks and logging each on its own
    // line keeps every line under that limit so the full payload always makes it to the console.
    private static let logChunkSize = 800

    private static func logFull(_ prefix: String, _ text: String) {
        guard text.count > logChunkSize else {
            NSLog("%@: %@", prefix, text)
            return
        }
        let chunks = stride(from: 0, to: text.count, by: logChunkSize).map { start -> Substring in
            let from = text.index(text.startIndex, offsetBy: start)
            let to = text.index(from, offsetBy: logChunkSize, limitedBy: text.endIndex) ?? text.endIndex
            return text[from..<to]
        }
        for (index, chunk) in chunks.enumerated() {
            NSLog("%@ [%d/%d]: %@", prefix, index + 1, chunks.count, String(chunk))
        }
    }
}

@available(iOS 13.0, *)
extension Chat360WebSocketClient: URLSessionWebSocketDelegate {}
