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
        var sessions = 1
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
                        return #"{"room_id":"\#(room.id)","room_name":\#(name),"status":"\#(room.status)","updated_at":"2026-09-18T10:00:00Z","session_count":\#(room.sessions)}"#
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

    /// Server rooms without the local records `setServerRooms` seeds, so the cache holds only what the
    /// repository itself synced (`agent-room:` rows).
    private func setUnseededServerRooms(_ rooms: [FakeRoom]) {
        RoomsServer.lock.lock(); RoomsServer.rooms = rooms; RoomsServer.lock.unlock()
    }

    private func syncedRoomTitles() async -> [String] {
        var cached: [CachedConversationEntity] = []
        for await list in cache.conversations(botId: botId) { cached = list; break }
        return cached.filter { $0.id.hasPrefix("agent-room:") }.map { $0.title }
    }

    private var requestLog: [String] {
        RoomsServer.seenRequests.map { "\($0.limit ?? "nil")/\($0.offset ?? "nil")" }
    }

    func testRefreshFetchesOnlyTheFirstPageAndReportsThatMoreIsAvailable() async {
        setUnseededServerRooms(named(120))

        let result = await repository.refreshRooms()

        XCTAssertEqual(result?.count, 50)
        XCTAssertTrue(repository.hasMoreRooms)
        XCTAssertEqual(requestLog, ["50/0"])
    }

    func testLoadMoreAddsTheNextPageUntilTheServerSaysThereIsNoMore() async {
        setUnseededServerRooms(named(120))
        _ = await repository.refreshRooms()

        let first = await repository.loadMoreRooms()
        let afterFirst = await syncedRoomTitles().count
        XCTAssertTrue(first)
        XCTAssertEqual(afterFirst, 100)
        XCTAssertTrue(repository.hasMoreRooms)

        let second = await repository.loadMoreRooms()
        let afterSecond = await syncedRoomTitles().count
        XCTAssertTrue(second)
        XCTAssertEqual(afterSecond, 120)
        XCTAssertFalse(repository.hasMoreRooms)
        XCTAssertEqual(RoomsServer.seenRequests.map { $0.offset ?? "nil" }, ["0", "50", "100"])
    }

    func testASinglePageOffersNoLoadMore() async {
        setUnseededServerRooms(named(5))

        let result = await repository.refreshRooms()

        XCTAssertEqual(result?.count, 5)
        XCTAssertFalse(repository.hasMoreRooms)
        XCTAssertEqual(RoomsServer.seenRequests.count, 1)
    }

    func testAnOlderChatBehindManyEmptyRoomsIsReachedByLoadingMore() async {
        // Newest-first, the front of the list is empty (never-used) rooms and the real conversation
        // sits past the first page.
        let empty = (1...110).map { FakeRoom(id: "empty-\($0)", name: "Empty \($0)", sessions: 0) }
        setUnseededServerRooms(empty + [FakeRoom(id: "old-real", name: "Creta is a good car")])

        let first = await repository.refreshRooms()
        XCTAssertEqual(first?.count, 0)
        _ = await repository.loadMoreRooms()
        _ = await repository.loadMoreRooms()

        let titles = await syncedRoomTitles()
        XCTAssertEqual(titles, ["Creta is a good car"])
    }

    func testAServerThatCapsAPageBelowTheRequestedSizeIsPagedByWhatItActuallyReturned() async {
        RoomsServer.serverMaxPage = 3
        setUnseededServerRooms(named(7))

        _ = await repository.refreshRooms()
        _ = await repository.loadMoreRooms()
        _ = await repository.loadMoreRooms()

        let titles = await syncedRoomTitles()
        XCTAssertEqual(titles.count, 7)
        XCTAssertEqual(RoomsServer.seenRequests.map { $0.offset ?? "nil" }, ["0", "3", "6"])
    }

    func testAServerThatIgnoresOffsetAndRepeatsOnePageCannotKeepLoadMoreAlive() async {
        RoomsServer.ignoreOffset = true
        RoomsServer.serverMaxPage = 3
        setUnseededServerRooms(named(9))

        _ = await repository.refreshRooms()
        _ = await repository.loadMoreRooms()

        let titles = await syncedRoomTitles()
        XCTAssertEqual(titles.count, 3, "duplicates were not collapsed")
    }

    func testRefreshAfterLoadingMoreReFetchesWhatWasAlreadyLoadedSoTheListDoesNotCollapse() async {
        setUnseededServerRooms(named(120))
        _ = await repository.refreshRooms()
        _ = await repository.loadMoreRooms() // 100 loaded

        _ = await repository.refreshRooms()

        XCTAssertEqual(requestLog.last, "100/0")
        let titles = await syncedRoomTitles()
        XCTAssertEqual(titles.count, 100)
    }

    func testAFailedLoadMoreReportsFailureAndLeavesTheListAsItWas() async {
        setUnseededServerRooms(named(120))
        _ = await repository.refreshRooms()
        RoomsServer.lock.lock(); RoomsServer.failFromOffset = 50; RoomsServer.lock.unlock()

        let ok = await repository.loadMoreRooms()

        XCTAssertFalse(ok)
        let titles = await syncedRoomTitles()
        XCTAssertEqual(titles.count, 50)
        XCTAssertTrue(repository.hasMoreRooms, "retry must still be offered")
    }

    func testAFailedRefreshReturnsNilAndLeavesTheCachedListUntouched() async {
        setUnseededServerRooms(named(4))
        let first = await repository.refreshRooms()
        XCTAssertEqual(first?.count, 4)

        RoomsServer.lock.lock(); RoomsServer.failFromOffset = 0; RoomsServer.lock.unlock()
        let result = await repository.refreshRooms()

        XCTAssertNil(result)
        let titles = await syncedRoomTitles()
        XCTAssertEqual(titles.count, 4)
    }

    func testInactiveRoomsAreListedAlongWithActiveOnes() async {
        setUnseededServerRooms(named(3) + (1...3).map { FakeRoom(id: "gone-\($0)", name: "Deleted \($0)", status: "INACTIVE") })

        let result = await repository.refreshRooms()

        XCTAssertEqual(result?.map { $0.title }.sorted(), ["Chat 1", "Chat 2", "Chat 3", "Deleted 1", "Deleted 2", "Deleted 3"])
    }
}
