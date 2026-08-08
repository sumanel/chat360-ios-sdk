import XCTest
@testable import Chat360SDK

/// End-to-end coverage of `ChatHistoryRepository`'s 401-retry-once logic against a real
/// `ThirdPartyTasksApiService` (backed by `StubURLProtocol`) - the point being to exercise the
/// actual `Chat360ApiError.httpError` status-code match, not a mock of it.
final class ChatHistoryRepositoryAuthRetryTests: XCTestCase {

    private var botId = ""

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
        // Unique per test so runs never collide inside the shared on-disk cache database.
        botId = "test-bot-\(UUID().uuidString)"
    }

    private func makeRepository() -> ChatHistoryRepository {
        let apiService = ThirdPartyTasksApiService(baseUrl: "https://example.invalid", session: StubURLProtocol.makeSession())
        return ChatHistoryRepository(
            apiService: apiService,
            tokenManager: ThirdPartyTokenManager(apiService: apiService, clientId: "client-1", apiKey: "api-key-1"),
            cache: .shared,
            clientId: "client-1",
            botId: botId,
            endUserId: "agent-1"
        )
    }

    private func tokenBody(_ bearerToken: String) -> String {
        """
        {"success":true,"data":{"bearer_token":"\(bearerToken)","token_type":"Bearer","expires_in":3600}}
        """
    }

    private func roomsListBody() -> String {
        """
        {"success":true,"data":{"client_id":"client-1","bot_id":"\(botId)","rooms":[
            {"room_id":"room-1","room_name":"Test Room","agent_id":"agent-1","status":"active",
             "session_ids":[],"session_count":0}
        ],"total_count":1,"has_more":false}}
        """
    }

    func testRefreshRoomsRetriesOnceAfterA401AndSucceedsWithTheRefreshedToken() async {
        StubURLProtocol.enqueue(statusCode: 200, body: tokenBody("token-1"))
        StubURLProtocol.enqueue(statusCode: 401, body: "")
        StubURLProtocol.enqueue(statusCode: 200, body: tokenBody("token-2"))
        StubURLProtocol.enqueue(statusCode: 200, body: roomsListBody())

        let succeeded = await makeRepository().refreshRooms()

        XCTAssertTrue(succeeded)
        XCTAssertEqual(StubURLProtocol.requestCount, 4)
        let headers = StubURLProtocol.recordedAuthorizationHeaders
        // [0] auth/token has no Authorization header; [1] rooms/list used the pre-refresh token.
        XCTAssertEqual(headers[1], "Bearer token-1")
        // [2] auth/token refresh; [3] retried rooms/list used the new token.
        XCTAssertEqual(headers[3], "Bearer token-2")
    }

    func testRefreshRoomsDoesNotRetryOnANon401Failure() async {
        StubURLProtocol.enqueue(statusCode: 200, body: tokenBody("token-1"))
        StubURLProtocol.enqueue(statusCode: 500, body: "")

        let succeeded = await makeRepository().refreshRooms()

        XCTAssertFalse(succeeded)
        XCTAssertEqual(StubURLProtocol.requestCount, 2)
    }

    func testRenameRoomIsBestEffortAndNeverThrowsOutToTheCaller() async {
        StubURLProtocol.enqueue(statusCode: 200, body: tokenBody("token-1"))
        StubURLProtocol.enqueue(statusCode: 500, body: "")

        // Must not throw/crash - this is the whole point of the best-effort contract.
        await makeRepository().renameRoom(roomId: "room-1", roomName: "New name")

        XCTAssertEqual(StubURLProtocol.requestCount, 2)
    }
}
