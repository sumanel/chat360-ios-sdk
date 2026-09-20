import XCTest
@testable import Chat360SDK

/// Only one room is ever connected, but a slow bot reply can land after the user has moved to another
/// room. Such a frame carries its own `room_id` and must be dropped, or two conversations end up in one chat.
final class RoomFrameRoutingTests: XCTestCase {

    /// Answers every session-init with the next room id: room-1, room-2, ...
    private final class NumberedRooms: URLProtocol {
        static let counter = Locked<Int>(wrappedValue: 0)
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func stopLoading() {}
        override func startLoading() {
            let url = request.url!
            let isSession = url.path.contains("/session/")
            // Only session-inits allocate a room; other requests (history etc.) must not advance the counter.
            let room = isSession ? NumberedRooms.counter.mutate { $0 += 1; return $0 } : 0
            let body = isSession
                ? Data(#"{"room_id":"room-\#(room)","owner_id":"owner-1","session_token":"tok","nodeType":"INIT","targetId":"t1"}"#.utf8)
                : Data()
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: isSession ? 200 : 404, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    private var repository: ChatRepository!
    private let seen = Locked<[String]>(wrappedValue: [])
    private var frameCounter = 0

    override func setUp() async throws {
        NumberedRooms.counter.mutate { $0 = 0 }
        seen.mutate { $0 = [] }
        frameCounter = 0
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [NumberedRooms.self]
        let baseUrl = "http://127.0.0.1:1"
        repository = ChatRepository(
            baseUrl: baseUrl,
            botId: "routing-bot-\(UUID().uuidString)",
            apiService: Chat360ApiService(baseUrl: baseUrl, session: URLSession(configuration: configuration)),
            wsClient: Chat360WebSocketClient()
        )
        await repository.connect(
            onEvent: { _ in }, onConnected: {}, onError: { _ in },
            onConversationStarted: { _ in false },
            onRawIncoming: { [seen] raw in seen.mutate { $0.append(raw) } }
        ) // room-1 is connected
    }

    override func tearDown() async throws {
        repository.disconnect()
    }

    /// Feeds a bot message for `room`; true when it got past the room guard (i.e. would reach the chat).
    private func deliver(_ room: String) -> Bool {
        frameCounter += 1
        let raw = #"{"user":"bot","room_id":"\#(room)","data":{"nodeType":"TEXT","nodeId":"n\#(frameCounter)","questionText":"msg-\#(frameCounter)-for-\#(room)"}}"#
        let before = seen.wrappedValue.count
        repository.handleIncoming(raw)
        return seen.wrappedValue.count > before
    }

    private func switchRoom() async {
        await repository.startNewSession()
    }

    func testAFrameForTheConnectedRoomIsDeliveredAndOneForAnotherRoomIsDropped() {
        XCTAssertTrue(deliver("room-1"))
        XCTAssertFalse(deliver("room-9"))
        XCTAssertEqual(seen.wrappedValue.count, 1)
    }

    func testALateReplyFromTheRoomTheUserJustLeftNeverReachesTheNewRoom() async {
        await switchRoom() // room-2
        XCTAssertFalse(deliver("room-1"), "the old room's reply leaked")
        XCTAssertTrue(deliver("room-2"), "the current room's reply was lost")
    }

    func testSwitchingThroughSeveralRoomsInARowOnlyEverAcceptsTheLastRoom() async {
        await switchRoom() // room-2
        await switchRoom() // room-3
        await switchRoom() // room-4
        let accepted = ["room-1", "room-2", "room-3", "room-4"].filter { deliver($0) }
        XCTAssertEqual(accepted, ["room-4"])
    }

    func testRepliesFromTwoRoomsInterleavedWhileSwitchingLandOnlyInTheConnectedRoom() async {
        var results: [(String, Bool)] = []
        results.append(("room-1", deliver("room-1")))
        await switchRoom() // room-2
        results.append(("room-1", deliver("room-1")))
        results.append(("room-2", deliver("room-2")))
        results.append(("room-1", deliver("room-1")))
        XCTAssertEqual(results.map { $0.0 }, ["room-1", "room-1", "room-2", "room-1"])
        XCTAssertEqual(results.map { $0.1 }, [true, false, true, false])
    }

    // MARK: onFreshSession - the role a newly created room was made with, before the server lists it

    func testABrandNewSessionReportsTheRoleItWasCreatedWith() async {
        let created = Locked<[String]>(wrappedValue: [])
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [NumberedRooms.self]
        let baseUrl = "http://127.0.0.1:1"
        NumberedRooms.counter.mutate { $0 = 0 }
        let repo = ChatRepository(
            baseUrl: baseUrl, botId: "fresh-\(UUID().uuidString)",
            apiService: Chat360ApiService(baseUrl: baseUrl, session: URLSession(configuration: configuration)),
            wsClient: Chat360WebSocketClient(),
            assistantVariables: ["agent_role": "customer"]
        )
        repo.onFreshSession = { roomId, variables in created.mutate { $0.append("\(roomId)=\(variables["agent_role"] ?? "-")") } }
        await repo.connect(onEvent: { _ in }, onConnected: {}, onError: { _ in }, onConversationStarted: { _ in false })

        repo.setAssistantVariables(["agent_role": "training"])
        await repo.startNewSession()
        repo.disconnect()

        XCTAssertEqual(created.wrappedValue, ["room-1=customer", "room-2=training"])
    }
}
