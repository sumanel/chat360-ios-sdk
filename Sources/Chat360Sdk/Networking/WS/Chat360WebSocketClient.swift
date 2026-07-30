import Foundation

/// Bare-bones `URLSessionWebSocketTask` wrapper: connect, send, receive raw text frames. No
/// heartbeat, reconnect, or ack-tracking here - those live in `HeartbeatManager`/`ReconnectManager`/
/// `AckTracker`, composed by `ChatRepository`.
final class Chat360WebSocketClient: NSObject {
    private var session: URLSession?
    private var task: URLSessionWebSocketTask?

    private var onOpen: (() -> Void)?
    private var onMessage: ((String) -> Void)?
    private var onClosed: ((_ code: Int, _ reason: String) -> Void)?
    private var onFailure: ((Error) -> Void)?

    func connect(
        wsUrl: String,
        onOpen: @escaping () -> Void,
        onMessage: @escaping (String) -> Void,
        onClosed: @escaping (_ code: Int, _ reason: String) -> Void,
        onFailure: @escaping (Error) -> Void
    ) {
        guard let url = URL(string: wsUrl) else {
            onFailure(Chat360WebSocketError.invalidURL(wsUrl))
            return
        }
        self.onOpen = onOpen
        self.onMessage = onMessage
        self.onClosed = onClosed
        self.onFailure = onFailure

        let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        self.session = session
        let task = session.webSocketTask(with: url)
        self.task = task
        task.resume()
        receiveNext()
    }

    private func receiveNext() {
        task?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let error):
                self.onFailure?(error)
            case .success(let message):
                switch message {
                case .string(let text):
                    self.onMessage?(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        self.onMessage?(text)
                    }
                @unknown default:
                    break
                }
                self.receiveNext()
            }
        }
    }

    /// Best-effort send, mirroring the Kotlin client's `webSocket?.send(text) ?: false`: returns
    /// whether there was a live task to attempt the send on, not delivery confirmation (which is
    /// what `AckTracker` is for).
    @discardableResult
    func send(_ text: String) -> Bool {
        guard let task else { return false }
        task.send(.string(text)) { [weak self] error in
            if let error {
                self?.onFailure?(error)
            }
        }
        return true
    }

    func close() {
        task?.cancel(with: .normalClosure, reason: Data("client closed".utf8))
        task = nil
        session?.invalidateAndCancel()
        session = nil
    }
}

extension Chat360WebSocketClient: URLSessionWebSocketDelegate {
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        onOpen?()
    }

    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {
        let reasonText = reason.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        onClosed?(closeCode.rawValue, reasonText)
    }
}

enum Chat360WebSocketError: Error {
    case invalidURL(String)
}
