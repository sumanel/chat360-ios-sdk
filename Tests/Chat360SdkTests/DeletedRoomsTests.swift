import XCTest
import SQLite3
@testable import Chat360SDK

/// "Room deletion is not working - the deleted room reappears as soon as the drawer is opened again": deleting only
/// asks the server to mark the room inactive, and `rooms/list` keeps returning inactive rooms, so the next refresh
/// put it straight back. A room deleted on this device now stays out of the list whatever the server returns.
final class DeletedRoomsTests: XCTestCase {

    private final class Server: URLProtocol {
        static let lock = NSLock()
        /// What the server keeps returning - including the rooms it has been told to mark inactive.
        static var rooms = ["a", "b", "c"]
        /// True makes the mark-inactive request fail, like an unreachable server.
        static var statusUpdateFails = false
        static var requestCount = 0

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func stopLoading() {}
        override func startLoading() {
            let url = request.url!
            var status = 200
            var body: Data
            Self.lock.lock(); Self.requestCount += 1; let ids = Self.rooms; let failing = Self.statusUpdateFails; Self.lock.unlock()
            if url.path.hasSuffix("/auth/token") {
                body = Data(#"{"success":true,"data":{"bearer_token":"token-1","token_type":"Bearer","expires_in":3600}}"#.utf8)
            } else if url.path.hasSuffix("/room/update/status") {
                status = failing ? 500 : 200
                body = Data(#"{"success":true,"data":{"room_id":"x","status":"INACTIVE"}}"#.utf8)
            } else {
                let rooms = ids.map { #"{"room_id":"\#($0)","room_name":"Chat \#($0)","status":"ACTIVE","updated_at":"2026-09-18T10:00:00Z","session_count":1}"# }.joined(separator: ",")
                body = Data(#"{"success":true,"data":{"rooms":[\#(rooms)],"total_count":\#(ids.count),"has_more":false}}"#.utf8)
            }
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    private final class MemoryDeletedStore: DeletedRoomStore {
        var saved: Set<String> = []
        func load(botId: String) -> Set<String> { saved }
        func add(botId: String, roomId: String) { saved.insert(roomId) }
    }

    override func setUp() {
        Server.lock.lock(); Server.rooms = ["a", "b", "c"]; Server.statusUpdateFails = false; Server.requestCount = 0; Server.lock.unlock()
    }

    private func repository(store: DeletedRoomStore?) -> ChatHistoryRepository {
        var handle: OpaquePointer?
        sqlite3_open(":memory:", &handle)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [Server.self]
        let api = ThirdPartyTasksApiService(baseUrl: "https://staging.test", session: URLSession(configuration: configuration))
        return ChatHistoryRepository(
            apiService: api,
            tokenManager: ThirdPartyTokenManager(apiService: api, clientId: "client-1", apiKey: "api-key-1"),
            cache: ChatCacheRepository(dao: ChatCacheDao(db: handle!)),
            clientId: "client-1", botId: "bot-1", endUserId: "agent-1", deletedRoomStore: store
        )
    }

    private func roomIds(_ repository: ChatHistoryRepository) async -> [String] {
        (await repository.refreshRooms() ?? []).compactMap { $0.roomId }.sorted()
    }

    func testADeletedRoomStaysOutOfTheListEvenThoughTheServerStillReturnsIt() async {
        let repo = repository(store: MemoryDeletedStore())
        let before = await roomIds(repo)
        XCTAssertEqual(before, ["a", "b", "c"])

        await repo.markRoomInactive(roomId: "b")

        let after = await roomIds(repo)
        XCTAssertEqual(after, ["a", "c"])
    }

    func testTheRoomStaysDeletedWhenTheServerRequestFails() async {
        let repo = repository(store: MemoryDeletedStore())
        _ = await repo.refreshRooms()
        Server.lock.lock(); Server.statusUpdateFails = true; Server.lock.unlock()

        await repo.markRoomInactive(roomId: "b")

        let after = await roomIds(repo)
        XCTAssertEqual(after, ["a", "c"])
    }

    func testADeleteIsRememberedAcrossLaunches() async {
        let store = MemoryDeletedStore()
        await repository(store: store).markRoomInactive(roomId: "b")

        let afterRestart = repository(store: store) // a new launch
        let after = await roomIds(afterRestart)
        XCTAssertEqual(after, ["a", "c"])
    }

    func testForgettingARoomTakesEffectImmediatelyAndWithoutAnyNetworkCall() async {
        let repo = repository(store: MemoryDeletedStore())
        _ = await repo.refreshRooms()
        Server.lock.lock(); let before = Server.requestCount; Server.lock.unlock()

        repo.forgetRoom(roomId: "a")

        Server.lock.lock(); let after = Server.requestCount; Server.lock.unlock()
        XCTAssertEqual(before, after)
        let ids = await roomIds(repo)
        XCTAssertFalse(ids.contains("a"))
    }
}
