import XCTest
import Network
@testable import Chat360SDK

/// `establishSession` awaits the network several times before it opens the socket. `disconnect()`
/// didn't invalidate it, so a session that was still in flight when the chat closed finished later
/// and opened a live socket for a repository nobody was listening to (`openSocket` even clears the
/// "manually disconnected" flag) - a leaked, unseen socket that then kept reconnecting.
final class EstablishSessionRaceTests: XCTestCase {

    /// Holds the session-init response until the test releases it.
    private final class GatedSessions: URLProtocol {
        static let gate = DispatchSemaphore(value: 0)
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func stopLoading() {}
        override func startLoading() {
            let url = request.url!
            let isSession = url.path.contains("/session/")
            let respond = { [self] in
                let body = isSession ? Data(#"{"room_id":"room-1","owner_id":"owner-1","session_token":"tok","nodeType":"INIT","targetId":"t1"}"#.utf8) : Data()
                client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: isSession ? 200 : 404, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: body)
                client?.urlProtocolDidFinishLoading(self)
            }
            if isSession {
                DispatchQueue.global().async { Self.gate.wait(); respond() }
            } else {
                respond()
            }
        }
    }

    func testDisconnectingWhileTheSessionIsStillBeingEstablishedNeverOpensASocket() async {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [GatedSessions.self]
        let baseUrl = "http://127.0.0.1:1"
        let socketClient = Chat360WebSocketClient()
        let repository = ChatRepository(
            baseUrl: baseUrl,
            botId: "establish-race-bot",
            apiService: Chat360ApiService(baseUrl: baseUrl, session: URLSession(configuration: configuration)),
            wsClient: socketClient
        )

        let connected = expectation(description: "connect() returned")
        Task {
            await repository.connect(onEvent: { _ in }, onConnected: {}, onError: { _ in }, onConversationStarted: { _ in false })
            connected.fulfill()
        }
        try? await Task.sleep(nanoseconds: 300_000_000) // session-init is now in flight

        repository.disconnect()
        GatedSessions.gate.signal() // ...and only now does it come back
        await fulfillment(of: [connected], timeout: 10)
        try? await Task.sleep(nanoseconds: 500_000_000)

        XCTAssertNil(socketClient.task, "a socket was opened after disconnect()")
    }

    func testAnUndisturbedSessionStillOpensItsSocket() async {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [GatedSessions.self]
        let baseUrl = "http://127.0.0.1:1"
        let socketClient = Chat360WebSocketClient()
        let repository = ChatRepository(
            baseUrl: baseUrl,
            botId: "establish-control-bot",
            apiService: Chat360ApiService(baseUrl: baseUrl, session: URLSession(configuration: configuration)),
            wsClient: socketClient
        )
        GatedSessions.gate.signal()

        await repository.connect(onEvent: { _ in }, onConnected: {}, onError: { _ in }, onConversationStarted: { _ in false })

        XCTAssertNotNil(socketClient.task, "the guard must not block a normal connect")
        repository.disconnect()
    }
}
