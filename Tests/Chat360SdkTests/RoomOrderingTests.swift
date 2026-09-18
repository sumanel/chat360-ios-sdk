import XCTest
import SQLite3
@testable import Chat360SDK

/// Regression tests for "latest chat isn't on top of history": the sidebar used to be ordered by
/// the rooms/list *response position* (`fetchedAt - index`), ignoring the timestamps the server
/// sends, so its order was whatever order the API happened to return.
final class RoomOrderingTests: XCTestCase {
    private let botId = "bot"

    private func makeCache() -> (ChatCacheRepository, ChatCacheDao) {
        var handle: OpaquePointer?
        sqlite3_open(":memory:", &handle)
        let dao = ChatCacheDao(db: handle!)
        return (ChatCacheRepository(dao: dao), dao)
    }

    /// Rooms only survive `thirdPartyRoomConversations` with a local user message (ghost filter).
    private func seedLocalRoom(_ dao: ChatCacheDao, roomId: String) async {
        let id = "local-\(roomId)"
        await dao.insertConversationIfMissing(CachedConversationEntity(id: id, botId: botId, roomId: roomId, createdAt: 1, updatedAt: 1))
        await dao.insertMessage(CachedMessageEntity(conversationId: id, kind: "USER", payload: "hi", createdAt: 1))
    }

    private func room(_ id: String, updatedAt: String?, createdAt: String? = nil) -> RoomDto {
        RoomDto(roomId: id, roomName: id, agentId: nil, status: nil, createdAt: createdAt, updatedAt: updatedAt, sessionIds: [], sessionCount: 0)
    }

    func testRoomsAreOrderedNewestFirstRegardlessOfServerOrder() async {
        let (cache, dao) = makeCache()
        for id in ["old", "newest", "middle"] { await seedLocalRoom(dao, roomId: id) }
        let response = [
            room("old", updatedAt: "2026-09-01T10:00:00Z"),
            room("newest", updatedAt: "2026-09-17T09:30:00.123456Z"),
            room("middle", updatedAt: "2026-09-10T12:00:00+00:00"),
        ]
        let forward = await cache.thirdPartyRoomConversations(botId: botId, rooms: response).map { $0.roomId }
        let reversed = await cache.thirdPartyRoomConversations(botId: botId, rooms: response.reversed()).map { $0.roomId }
        XCTAssertEqual(forward, ["newest", "middle", "old"])
        XCTAssertEqual(reversed, ["newest", "middle", "old"])
    }

    func testUpdatedAtWinsOverCreatedAtAndCreatedAtIsTheFallback() async {
        let (cache, dao) = makeCache()
        for id in ["a", "b"] { await seedLocalRoom(dao, roomId: id) }
        let result = await cache.thirdPartyRoomConversations(botId: botId, rooms: [
            room("a", updatedAt: "2026-09-02T00:00:00Z", createdAt: "2026-09-16T00:00:00Z"),
            room("b", updatedAt: nil, createdAt: "2026-09-10T00:00:00Z"),
        ])
        XCTAssertEqual(result.map { $0.roomId }, ["b", "a"])
    }

    func testALocallyNewerSendIsNotRolledBackByASyncWhoseServerTimestampLags() async {
        let (cache, dao) = makeCache()
        for id in ["a", "b"] { await seedLocalRoom(dao, roomId: id) }
        let server = [room("a", updatedAt: "2026-09-01T00:00:00Z"), room("b", updatedAt: "2026-09-05T00:00:00Z")]
        await cache.syncAgentRooms(botId: botId, conversations: await cache.thirdPartyRoomConversations(botId: botId, rooms: server))

        // The user just messaged the older room "a" on this device.
        let a = await dao.findConversation(botId: botId, roomId: "a")!
        await dao.touch(conversationId: a.id, updatedAt: Int64(Date().timeIntervalSince1970 * 1000), botId: botId)
        // The next refresh still reports the stale server time for "a".
        await cache.syncAgentRooms(botId: botId, conversations: await cache.thirdPartyRoomConversations(botId: botId, rooms: server))

        var order: [String?] = []
        for await list in cache.conversations(botId: botId) { order = list.map { $0.roomId }; break }
        XCTAssertEqual(order.first ?? nil, "a")
    }

    func testTimestampParserHandlesEpochAndIsoFormats() {
        let expected: Int64 = 1_757_500_000_000
        XCTAssertEqual(ChatCacheRepository.parseServerTimestampMs("1757500000"), expected)
        XCTAssertEqual(ChatCacheRepository.parseServerTimestampMs("1757500000000"), expected)
        XCTAssertEqual(ChatCacheRepository.parseServerTimestampMs("2025-09-10T10:26:40Z"), expected)
        XCTAssertEqual(ChatCacheRepository.parseServerTimestampMs("2025-09-10T15:56:40+05:30"), expected)
        XCTAssertEqual(ChatCacheRepository.parseServerTimestampMs("2025-09-10 10:26:40"), expected)
        XCTAssertEqual(ChatCacheRepository.parseServerTimestampMs("2025-09-10T10:26:40.123456Z"), expected + 123)
        XCTAssertNil(ChatCacheRepository.parseServerTimestampMs(nil))
        XCTAssertNil(ChatCacheRepository.parseServerTimestampMs("not a date"))
    }

    // MARK: - Twin rows (same chat listed twice after a refresh)

    private func list(_ cache: ChatCacheRepository) async -> [CachedConversationEntity] {
        for await list in cache.conversations(botId: botId) { return list }
        return []
    }

    func testARoomThisDeviceAlreadyHasIsNotListedASecondTimeAfterARefresh() async {
        let (cache, dao) = makeCache()
        await dao.upsertConversation(CachedConversationEntity(id: "local-1", botId: botId, roomId: "room-1", title: "creta is good car", createdAt: 1, updatedAt: 5))
        await dao.insertMessage(CachedMessageEntity(conversationId: "local-1", kind: "USER", payload: "hi", createdAt: 1))

        await cache.syncAgentRooms(botId: botId, conversations: await cache.thirdPartyRoomConversations(botId: botId, rooms: [room("room-1", updatedAt: "2026-09-17T10:00:00Z")]))

        let rows = await list(cache)
        XCTAssertEqual(rows.map { $0.id }, ["local-1"])
        XCTAssertEqual(rows.first?.title, "creta is good car")
    }

    func testAnExistingTwinFromAnEarlierRefreshIsCleanedUpAndTheRoomResolvesToTheLocalRow() async {
        let (cache, dao) = makeCache()
        await dao.upsertConversation(CachedConversationEntity(id: "local-1", botId: botId, roomId: "room-1", title: "creta is good car", createdAt: 1, updatedAt: 5))
        await dao.insertMessage(CachedMessageEntity(conversationId: "local-1", kind: "USER", payload: "hi", createdAt: 1))
        await dao.upsertConversation(CachedConversationEntity(id: "agent-room:room-1", botId: botId, roomId: "room-1", title: "Conversation", createdAt: 1, updatedAt: 9_999_999_999_999))

        await cache.syncAgentRooms(botId: botId, conversations: await cache.thirdPartyRoomConversations(botId: botId, rooms: [room("room-1", updatedAt: "2026-09-17T10:00:00Z")]))

        let ids = await list(cache).map { $0.id }
        XCTAssertEqual(ids, ["local-1"])
        let found = await dao.findConversation(botId: botId, roomId: "room-1")
        XCTAssertEqual(found?.id, "local-1")
    }
}
