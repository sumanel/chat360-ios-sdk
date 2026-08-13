import Foundation

@available(iOS 13.0, *)
public final class Chat360WebSocketClient: NSObject {
    private let session: URLSession
    private var task: URLSessionWebSocketTask?
    private var onOpen: (() -> Void)?
    private var onMessage: ((String) -> Void)?
    private var onClosed: ((Int, String) -> Void)?
    private var onFailure: ((Error) -> Void)?

    public init(session: URLSession = URLSession(configuration: .default)) {
        self.session = session
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
        self.onOpen = onOpen
        self.onMessage = onMessage
        self.onClosed = onClosed
        self.onFailure = onFailure

        guard let url = URL(string: wsUrl) else {
            onFailure(URLError(.badURL))
            return
        }
        let request = URLRequest(url: url)
        let newTask = session.webSocketTask(with: request)
        task = newTask
        newTask.resume()
        onOpen()
        NSLog("[Chat360WS] Socket OPEN -> %@", wsUrl)
        listen()
    }

    private func listen() {
        task?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    NSLog("[Chat360WS] << RECEIVED: %@", text)
                    self.onMessage?(text)
                case .data(let data):
                    let text = String(data: data, encoding: .utf8) ?? ""
                    NSLog("[Chat360WS] << RECEIVED (data): %@", text)
                    self.onMessage?(text)
                @unknown default:
                    break
                }
                self.listen()
            case .failure(let error):
                NSLog("[Chat360WS] Socket FAILURE: %@", error.localizedDescription)
                self.onFailure?(error)
            }
        }
    }

    @discardableResult
    public func send(_ text: String) -> Bool {
        guard let task, task.state == .running else {
            NSLog("[Chat360WS] >> SEND FAILED (socket not open): %@", text)
            return false
        }
        task.send(.string(text)) { [weak self] error in
            if let error {
                NSLog("[Chat360WS] >> SEND FAILED: %@", error.localizedDescription)
                self?.onFailure?(error)
            }
        }
        NSLog("[Chat360WS] >> SENT: %@", text)
        return true
    }

    public func close() {
        NSLog("[Chat360WS] Closing socket (client requested)")
        task?.cancel(with: .normalClosure, reason: "client closed".data(using: .utf8))
        let code = 1000
        onClosed?(code, "client closed")
        task = nil
    }
}
