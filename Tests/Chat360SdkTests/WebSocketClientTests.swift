import XCTest
import Network
@testable import Chat360SDK

/// Regression tests for duplicate sockets: opening a new connection used to leave the previous
/// task running (its callbacks were ignored, so nothing ever closed it), leaking a live socket per
/// stacked reconnect.
final class WebSocketClientTests: XCTestCase {

    /// A local TCP server that accepts connections and never answers, so a websocket task pointed at
    /// it stays `.running` until something cancels it - unlike a refused connection, which ends by
    /// itself and would make "was it cancelled?" impossible to tell apart from "did it fail?".
    private var listener: NWListener?
    private var heldConnections: [NWConnection] = []
    private var silentServerPort: UInt16 = 1

    override func setUp() {
        super.setUp()
        guard let listener = try? NWListener(using: .tcp, on: .any) else { return }
        listener.newConnectionHandler = { [weak self] connection in
            connection.start(queue: .global())
            self?.heldConnections.append(connection)
        }
        let ready = expectation(description: "listener ready")
        listener.stateUpdateHandler = { state in if case .ready = state { ready.fulfill() } }
        listener.start(queue: .global())
        wait(for: [ready], timeout: 5)
        self.listener = listener
        silentServerPort = listener.port?.rawValue ?? 1
    }

    override func tearDown() {
        listener?.cancel()
        heldConnections.forEach { $0.cancel() }
        super.tearDown()
    }

    private func connect(_ client: Chat360WebSocketClient, onClosed: @escaping (Int, String) -> Void = { _, _ in }) {
        client.connect(wsUrl: "ws://127.0.0.1:\(silentServerPort)/ws", onOpen: {}, onMessage: { _ in }, onClosed: onClosed, onFailure: { _ in })
    }

    private func awaitNotRunning(_ task: URLSessionWebSocketTask?) -> Bool {
        let deadline = Date().addingTimeInterval(3)
        while task?.state == .running, Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.02)) }
        return task?.state != .running
    }

    func testConnectingAgainCancelsThePreviousSocket() {
        let client = Chat360WebSocketClient()
        connect(client)
        let first = client.task
        XCTAssertNotNil(first)
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        XCTAssertEqual(first?.state, .running, "test setup: the silent server should keep the first socket pending")

        connect(client)

        XCTAssertTrue(awaitNotRunning(first), "the replaced socket was left running")
        XCTAssertFalse(client.task === first)
        client.close()
    }

    func testClosingReportsBackExactlyOnceAndClearsTheSocket() {
        let client = Chat360WebSocketClient()
        var closed: [Int] = []
        connect(client) { code, _ in closed.append(code) }

        client.close()
        client.close()

        XCTAssertEqual(closed, [1000], "an intentional close must be reported once, and only for the live connection")
        XCTAssertNil(client.task)
    }

    func testReplacedSocketIsNeverReportedAsClosed() {
        let client = Chat360WebSocketClient()
        var firstClosed = 0
        connect(client) { _, _ in firstClosed += 1 }
        connect(client) // supersedes the first

        let settled = expectation(description: "old socket's late events settle")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { settled.fulfill() }
        wait(for: [settled], timeout: 3)

        XCTAssertEqual(firstClosed, 0, "a replaced socket's close was delivered as the live socket's")
        client.close()
    }
}
