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
    private var task: URLSessionWebSocketTask?
    private var callbacks: Callbacks?

    /// Bumped on every connect()/close() so callbacks from a superseded
    /// connection (in-flight receive/send completions from an old task)
    /// are dropped instead of firing into the current connection's state.
    private var generation: Int = 0

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
        generation += 1
        let myGeneration = generation
        callbacks = Callbacks(onOpen: onOpen, onMessage: onMessage, onClosed: onClosed, onFailure: onFailure)

        guard let url = URL(string: wsUrl) else {
            onFailure(URLError(.badURL))
            return
        }
        let request = URLRequest(url: url)
        let newTask = session.webSocketTask(with: request)
        task = newTask
        newTask.resume()
        listen(generation: myGeneration)
    }

    public func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didOpenWithProtocol protocol: String?
    ) {
        guard task === webSocketTask, let callbacks else { return }
        NSLog("[Chat360WS] Socket OPEN")
        callbacks.onOpen()
    }

    public func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {
        guard task === webSocketTask, let callbacks else { return }
        let reasonText = reason.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        NSLog("[Chat360WS] Socket CLOSED by server: %d %@", closeCode.rawValue, reasonText)
        callbacks.onClosed(closeCode.rawValue, reasonText)
    }

    private func listen(generation myGeneration: Int) {
        task?.receive { [weak self] result in
            guard let self else { return }
            // A newer connect()/close() has superseded this one; let this
            // receive chain die instead of touching the current connection.
            guard myGeneration == self.generation, let callbacks = self.callbacks else { return }
            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    NSLog("[Chat360WS] << RECEIVED: %@", text)
                    callbacks.onMessage(text)
                case .data(let data):
                    let text = String(data: data, encoding: .utf8) ?? ""
                    NSLog("[Chat360WS] << RECEIVED (data): %@", text)
                    callbacks.onMessage(text)
                @unknown default:
                    break
                }
                self.listen(generation: myGeneration)
            case .failure(let error):
                NSLog("[Chat360WS] Socket FAILURE: %@", error.localizedDescription)
                callbacks.onFailure(error)
            }
        }
    }

    @discardableResult
    public func send(_ text: String) -> Bool {
        guard let task, task.state == .running else {
            NSLog("[Chat360WS] >> SEND FAILED (socket not open): %@", text)
            return false
        }
        let myGeneration = generation
        task.send(.string(text)) { [weak self] error in
            guard let self, let error else { return }
            guard myGeneration == self.generation else { return }
            NSLog("[Chat360WS] >> SEND FAILED: %@", error.localizedDescription)
            self.callbacks?.onFailure(error)
        }
        NSLog("[Chat360WS] >> SENT: %@", text)
        return true
    }

    public func close() {
        NSLog("[Chat360WS] Closing socket (client requested)")
        generation += 1
        let closedCallbacks = callbacks
        task?.cancel(with: .normalClosure, reason: "client closed".data(using: .utf8))
        task = nil
        callbacks = nil
        closedCallbacks?.onClosed(1000, "client closed")
    }
}

@available(iOS 13.0, *)
extension Chat360WebSocketClient: URLSessionWebSocketDelegate {}
