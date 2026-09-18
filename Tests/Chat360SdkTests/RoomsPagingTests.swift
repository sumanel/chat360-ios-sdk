import XCTest
import SQLite3
@testable import Chat360SDK

/// Regression tests for the history list silently dropping older chats. `rooms/list` called with no
/// `limit` returns only the server's default page (20 rooms, newest first) and sets `has_more`; the SDK
/// never asked for the rest. Soft-deleted rooms count toward that page, so as they piled up the real,
/// older chats fell off the end of the list.
final class RoomsPagingTests: XCTestCase {

    struct FakeRoom {
        let id: String
        let name: String?
        var status = "active"
    }

    /// Behaves like the real endpoint: honours limit/offset, defaults to a page of 20, reports has_more.
    private final class RoomsServer: URLProtocol {
        static let lock = NSLock()
        static var rooms: [FakeRoom] = []
        static var serverMaxPage = 100
        static var defaultPage = 20
        static var ignoreOffset = false
        static var failFromOffset: Int?
        static var requests: [(limit: String?, offset: String?)] = []

        static func reset() {
            lock.lock(); defer { lock.unlock() }
            rooms = []; serverMaxPage = 100; defaultPage = 20; ignoreOffset = false; failFromOffset = nil; requests = []
        }
        static var seenRequests: [(limit: String?, offset: String?)] { lock.lock(); defer { lock.unlock() }; return requests }

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func stopLoading() {}

        override func startLoading() {
            let url = request.url!
            var status = 200
            var body = Data()
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let query = { (name: String) in items.first { $0.name == name }?.value }
            if url.path.hasSuffix("/auth/token") {
                body = Data(#"{"success":true,"data":{"bearer_token":"token-1","token_type":"Bearer","expires_in":3600}}"#.utf8)
            } else {
                Self.lock.lock()
                Self.requests.append((query("limit"), query("offset")))
                let start = Self.ignoreOffset ? 0 : (query("offset").flatMap(Int.init) ?? 0)
                let size = min(query("limit").flatMap(Int.init) ?? Self.defaultPage, Self.serverMaxPage)
                let all = Self.rooms
                let failing = Self.failFromOffset.map { start >= $0 } ?? false
                Self.lock.unlock()
                if failing {
                    status = 500
                } else {
                    let page = Array(all.dropFirst(start).prefix(size))
                    let rooms = page.map { room -> String in
                        let name = room.name.map { "\"\($0)\"" } ?? "null"
                        return #"{"room_id":"\#(room.id)","room_name":\#(name),"status":"\#(room.status)","updated_at":"2026-09-18T10:00:00Z","session_count":1}"#
                    }.joined(separator: ",")
                    body = Data(#"{"success":true,"data":{"rooms":[\#(rooms)],"total_count":\#(all.count),"has_more":\#(start + page.count < all.count)}}"#.utf8)
                }
            }
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    private let botId = "bot-1"
    private var dao: ChatCacheDao!
    private var cache: ChatCacheRepository!
    private var repository: ChatHistoryRepository!

    override func setUp() {
        RoomsServer.reset()
        var handle: OpaquePointer?
        sqlite3_open(":memory:", &handle)
        dao = ChatCacheDao(db: handle!)
        cache = ChatCacheRepository(dao: dao)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RoomsServer.self]
        let api = ThirdPartyTasksApiService(baseUrl: "https://staging.test", session: URLSession(configuration: configuration))
        repository = ChatHistoryRepository(apiService: api, tokenManager: ThirdPartyTokenManager(apiService: api, clientId: "client-1", apiKey: "api-key-1"), cache: cache, clientId: "client-1", botId: botId, endUserId: "agent-1")
    }

    /// iOS only lists a server room the user actually sent something in on this device, so give every
    /// fake room a local record first (the same thing a real chat leaves behind).
    private func seedLocalRecords(for rooms: [FakeRoom]) async {
        for room in rooms {
            let id = "local-\(room.id)"
            await dao.insertConversationIfMissing(CachedConversationEntity(id: id, botId: botId, roomId: room.id, createdAt: 1, updatedAt: 1))
            await dao.insertMessage(CachedMessageEntity(conversationId: id, kind: "USER", payload: "hi", createdAt: 1))
        }
    }

    private func named(_ count: Int, prefix: String = "Chat") -> [FakeRoom] {
        (1...count).map { FakeRoom(id: "\(prefix)-\($0)", name: "\(prefix) \($0)") }
    }

    private func setServerRooms(_ rooms: [FakeRoom]) async {
        RoomsServer.lock.lock(); RoomsServer.rooms = rooms; RoomsServer.lock.unlock()
        await seedLocalRecords(for: rooms)
    }

    func testEveryPageIsFetchedNotJustTheServersDefaultFirstPage() async {
        await setServerRooms(named(250))

        let result = await repository.refreshRooms()

        XCTAssertEqual(result?.count, 250, "only part of the list was fetched")
        XCTAssertEqual(RoomsServer.seenRequests.map { "\($0.limit ?? "nil")/\($0.offset ?? "nil")" }, ["100/0", "100/100", "100/200"])
    }

    func testAnOlderRealChatBehindManyDeletedRoomsStillShowsUp() async {
        // The reported shape: newest-first, the front of the list is soft-deleted rooms and the real
        // conversation sits past the server's default page of 20.
        let deleted = (1...110).map { FakeRoom(id: "gone-\($0)", name: "Deleted \($0)", status: "INACTIVE") }
        await setServerRooms(deleted + [FakeRoom(id: "old-real", name: "Creta is a good car")])

        let result = await repository.refreshRooms()

        XCTAssertEqual(result?.map { $0.title }, ["Creta is a good car"])
    }

    func testAServerThatCapsAPageBelowTheRequestedSizeIsPagedByWhatItActuallyReturned() async {
        RoomsServer.serverMaxPage = 3
        await setServerRooms(named(7))

        let result = await repository.refreshRooms()

        XCTAssertEqual(result?.count, 7)
        XCTAssertEqual(RoomsServer.seenRequests.map { $0.offset ?? "nil" }, ["0", "3", "6"])
    }

    func testASinglePageMakesASingleRequest() async {
        await setServerRooms(named(5))

        let result = await repository.refreshRooms()

        XCTAssertEqual(result?.count, 5)
        XCTAssertEqual(RoomsServer.seenRequests.count, 1)
    }

    func testAServerThatIgnoresOffsetAndRepeatsOnePageCannotLoopForever() async {
        RoomsServer.ignoreOffset = true
        RoomsServer.serverMaxPage = 3
        await setServerRooms(named(9))

        let result = await repository.refreshRooms()

        XCTAssertEqual(result?.count, 3, "duplicates were not collapsed")
        XCTAssertLessThanOrEqual(RoomsServer.seenRequests.count, 2, "kept requesting: \(RoomsServer.seenRequests)")
    }

    func testAFailureOnALaterPageFailsTheWholeRefreshAndLeavesTheCachedListUntouched() async {
        // Four synced rooms the user has chatted in, all sitting on the THIRD page of the server's list.
        let onLaterPage = (200...203).map { "Chat-\($0)" }
        for roomId in onLaterPage {
            let id = "agent-room:\(roomId)"
            await dao.upsertConversation(CachedConversationEntity(id: id, botId: botId, roomId: roomId, title: roomId, createdAt: 1, updatedAt: 1))
            await dao.insertMessage(CachedMessageEntity(conversationId: id, kind: "USER", payload: "hi", createdAt: 1))
        }
        RoomsServer.lock.lock(); RoomsServer.rooms = named(250); RoomsServer.failFromOffset = 100; RoomsServer.lock.unlock() // page 2 blows up

        let result = await repository.refreshRooms()

        XCTAssertNil(result, "a partial list was returned as if it were complete")
        // The sync deletes cached agent rooms missing from the fetched list - handed only the first
        // pages, it would have wiped every room that lives on the pages that never loaded.
        var cached: [CachedConversationEntity] = []
        for await list in cache.conversations(botId: botId) { cached = list; break }
        XCTAssertEqual(cached.filter { $0.id.hasPrefix("agent-room:") }.count, 4, "cached rooms were deleted by a partial refresh")
    }

    func testSoftDeletedRoomsAreStillDroppedAfterPaging() async {
        await setServerRooms(named(3) + (1...3).map { FakeRoom(id: "gone-\($0)", name: "Deleted \($0)", status: "INACTIVE") })

        let result = await repository.refreshRooms()

        XCTAssertEqual(result?.map { $0.title }.sorted(), ["Chat 1", "Chat 2", "Chat 3"])
    }
}
