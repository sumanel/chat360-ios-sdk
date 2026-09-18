import XCTest
import Network
@testable import Chat360SDK

/// `ChatRepository`'s socket/session state used to be read and written, unguarded, from the main
/// thread (sends, retries), the socket's delegate queue (open/close/frames), the timer queue
/// (reconnect, heartbeat, ack retries) and the concurrency pool. `ensureReconnecting()` in
/// particular ran off the main thread on every resend while the main thread did the same.
///
/// This drives those entry points concurrently against a live repository. Under Thread Sanitizer
/// (`-enableThreadSanitizer YES`) an unguarded field fails the run; without it the same traffic
/// still tends to crash outright or corrupt memory if the guards regress.
final class RepositoryThreadSafetyTests: XCTestCase {

    /// Answers session-init and 404s everything else, without touching the network.
    private final class StubSessions: URLProtocol {
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func stopLoading() {}
        override func startLoading() {
            let url = request.url!
            let isSession = url.path.contains("/session/")
            let body = isSession ? Data(#"{"room_id":"room-1","owner_id":"owner-1","session_token":"tok","nodeType":"INIT","targetId":"t1"}"#.utf8) : Data()
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: isSession ? 200 : 404, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    private var listener: NWListener?
    private var held: [NWConnection] = []
    private var port: UInt16 = 1

    /// A TCP server that accepts and never answers, so sockets stay mid-connect like a flaky network.
    override func setUp() {
        super.setUp()
        guard let listener = try? NWListener(using: .tcp, on: .any) else { return }
        listener.newConnectionHandler = { [weak self] connection in
            connection.start(queue: .global())
            self?.held.append(connection)
        }
        let ready = expectation(description: "listener ready")
        listener.stateUpdateHandler = { if case .ready = $0 { ready.fulfill() } }
        listener.start(queue: .global())
        wait(for: [ready], timeout: 5)
        self.listener = listener
        port = listener.port?.rawValue ?? 1
    }

    override func tearDown() {
        listener?.cancel()
        held.forEach { $0.cancel() }
        super.tearDown()
    }

    func testResendsReconnectsAndTeardownFromEveryThreadAreSafe() async {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubSessions.self]
        let baseUrl = "http://127.0.0.1:\(port)"
        let repository = ChatRepository(
            baseUrl: baseUrl,
            botId: "thread-safety-bot",
            apiService: Chat360ApiService(baseUrl: baseUrl, session: URLSession(configuration: configuration))
        )
        await repository.connect(onEvent: { _ in }, onConnected: {}, onError: { _ in }, onConversationStarted: { _ in false })

        let done = expectation(description: "stress finished")
        DispatchQueue.global().async {
            DispatchQueue.concurrentPerform(iterations: 600) { i in
                switch i % 6 {
                case 0, 1, 2: _ = repository.sendFreeText("message \(i)") // main-thread send / retry path
                case 3: repository.reconnectNow()                        // close + reopen
                case 4: _ = repository.sendFreeText("retry \(i)")
                default: repository.reconnectNow()
                }
            }
            done.fulfill()
        }
        await fulfillment(of: [done], timeout: 60)
        // Let the socket callbacks and 5s-backoff reconnect timers queued by all that settle.
        try? await Task.sleep(nanoseconds: 700_000_000)
        repository.disconnect()
    }
}
