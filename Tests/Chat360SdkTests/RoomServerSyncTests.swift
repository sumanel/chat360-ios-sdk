import XCTest
import SQLite3
@testable import Chat360SDK

/// The dashboard list must follow the server: no empty rooms, rooms with messages shown even when
/// unnamed, and rooms this device already had a local row for still synced (deleted / renamed).
final class RoomServerSyncTests: XCTestCase {
    private let botId = "bot"

    private func makeCache() -> (ChatCacheRepository, ChatCacheDao) {
        var handle: OpaquePointer?
        sqlite3_open(":memory:", &handle)
        let dao = ChatCacheDao(db: handle!)
        return (ChatCacheRepository(dao: dao), dao)
    }

    private func room(_ id: String, name: String = "", status: String = "active", sessions: Int? = 1) -> RoomDto {
        RoomDto(roomId: id, roomName: name, agentId: nil, status: status, createdAt: nil, updatedAt: "2026-09-19T05:00:00Z", sessionIds: [], sessionCount: sessions)
    }

    private func sync(_ cache: ChatCacheRepository, _ rooms: [RoomDto]) async -> [CachedConversationEntity] {
        await cache.syncLocalConversations(botId: botId, rooms: rooms)
        await cache.syncAgentRooms(botId: botId, conversations: await cache.thirdPartyRoomConversations(botId: botId, rooms: rooms))
        var result: [CachedConversationEntity] = []
        for await list in cache.conversations(botId: botId) { result = list; break }
        return result
    }

    func testEmptyRoomIsNotListedEvenWithAName() async {
        let (cache, _) = makeCache()
        let list = await sync(cache, [room("empty", name: "x", sessions: 0), room("used", name: "hello")])
        XCTAssertEqual(list.map { $0.id }, ["agent-room:used"])
    }

    func testUnnamedRoomWithMessagesIsListed() async {
        let (cache, _) = makeCache()
        let list = await sync(cache, [room("r1", name: "", sessions: 2)])
        XCTAssertEqual(list.map { $0.title }, ["Conversation"])
    }

    func testRoomWithNoNameAndNoCountIsTreatedAsEmpty() async {
        let (cache, _) = makeCache()
        let list = await sync(cache, [room("r1", name: "", sessions: nil)])
        XCTAssertTrue(list.isEmpty)
    }

    func testLocalChatTheServerMarksInactiveIsRemoved() async {
        let (cache, dao) = makeCache()
        await dao.insertConversationIfMissing(CachedConversationEntity(id: "local-1", botId: botId, roomId: "r1", title: "old chat", createdAt: 1, updatedAt: 5))
        let list = await sync(cache, [room("r1", name: "old chat", status: "INACTIVE")])
        XCTAssertTrue(list.isEmpty)
    }

    func testLocalChatTakesTheNameTheServerHolds() async {
        let (cache, dao) = makeCache()
        await dao.insertConversationIfMissing(CachedConversationEntity(id: "local-1", botId: botId, roomId: "r1", title: "hi", createdAt: 1, updatedAt: 5))
        let list = await sync(cache, [room("r1", name: "Venue features")])
        XCTAssertEqual(list.map { $0.id }, ["local-1"])
        XCTAssertEqual(list.map { $0.title }, ["Venue features"])
    }
}
