import XCTest
import SQLite3
@testable import Chat360SDK

/// `rooms/list` returns each room's `agent_role`; the history list badges rooms from it.
final class RoomRolesTests: XCTestCase {

    private final class RolesServer: URLProtocol {
        static let lock = NSLock()
        /// roomId -> role (nil = the field is absent)
        static var rooms: [(id: String, role: String?)] = []
        static func set(_ rooms: [(id: String, role: String?)]) { lock.lock(); self.rooms = rooms; lock.unlock() }

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func stopLoading() {}
        override func startLoading() {
            let url = request.url!
            var body: Data
            if url.path.hasSuffix("/auth/token") {
                body = Data(#"{"success":true,"data":{"bearer_token":"token-1","token_type":"Bearer","expires_in":3600}}"#.utf8)
            } else {
                Self.lock.lock(); let all = Self.rooms; Self.lock.unlock()
                let rooms = all.map { room -> String in
                    let role = room.role.map { #","agent_role":"\#($0)""# } ?? ""
                    return #"{"room_id":"\#(room.id)","room_name":"Chat \#(room.id)","status":"active","updated_at":"2026-09-18T10:00:00Z","session_count":1\#(role)}"#
                }.joined(separator: ",")
                body = Data(#"{"success":true,"data":{"rooms":[\#(rooms)],"total_count":\#(all.count),"has_more":false}}"#.utf8)
            }
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    private final class MemoryRoleStore: RoomRoleStore {
        var saved: [String: String]
        var savedLocal: [String: String]
        var saves = 0
        init(_ saved: [String: String] = [:], local: [String: String] = [:]) { self.saved = saved; self.savedLocal = local }
        func load(botId: String) -> [String: String] { saved }
        func save(botId: String, roles: [String: String]) { saved = roles; saves += 1 }
        func loadLocal(botId: String) -> [String: String] { savedLocal }
        func saveLocal(botId: String, roles: [String: String]) { savedLocal = roles }
    }

    private func repository(store: RoomRoleStore? = nil) -> ChatHistoryRepository {
        var handle: OpaquePointer?
        sqlite3_open(":memory:", &handle)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RolesServer.self]
        let api = ThirdPartyTasksApiService(baseUrl: "https://staging.test", session: URLSession(configuration: configuration))
        return ChatHistoryRepository(
            apiService: api,
            tokenManager: ThirdPartyTokenManager(apiService: api, clientId: "client-1", apiKey: "api-key-1"),
            cache: ChatCacheRepository(dao: ChatCacheDao(db: handle!)),
            clientId: "client-1", botId: "bot-1", endUserId: "agent-1", roleStore: store
        )
    }

    override func setUp() { RolesServer.set([]) }

    func testTheRolesTheServerReturnsAreKeptPerRoom() async {
        RolesServer.set([("room-a", "training"), ("room-b", "customer")])
        let repo = repository()
        _ = await repo.refreshRooms()
        XCTAssertEqual(repo.roomRoles, ["room-a": "training", "room-b": "customer"])
    }

    func testARoomTheServerGivesNoRoleForHasNone() async {
        RolesServer.set([("room-a", "training"), ("room-b", nil)])
        let repo = repository()
        _ = await repo.refreshRooms()
        XCTAssertEqual(repo.roomRoles, ["room-a": "training"])
    }

    func testABlankRoleIsIgnored() async {
        RolesServer.set([("room-a", "  ")])
        let repo = repository()
        _ = await repo.refreshRooms()
        XCTAssertEqual(repo.roomRoles, [:])
    }

    func testRolesAreSavedAndComeBackBeforeTheNextFetch() async {
        RolesServer.set([("room-a", "training")])
        let store = MemoryRoleStore()
        _ = await repository(store: store).refreshRooms()
        XCTAssertEqual(store.saved, ["room-a": "training"])

        let reopened = repository(store: store) // a new launch, offline: nothing fetched yet
        XCTAssertEqual(reopened.roomRoles, ["room-a": "training"])
    }

    func testALaterFetchAddsRoomsAndKeepsTheOnesNotInThisPage() async {
        let repo = repository(store: MemoryRoleStore(["room-old": "customer"]))
        RolesServer.set([("room-new", "training")])
        _ = await repo.refreshRooms()
        XCTAssertEqual(repo.roomRoles, ["room-old": "customer", "room-new": "training"])
    }

    func testTheRoleIsTrimmed() async {
        RolesServer.set([("room-a", "  training ")])
        let repo = repository()
        _ = await repo.refreshRooms()
        XCTAssertEqual(repo.roomRoles, ["room-a": "training"])
    }

    func testTheServerIsTheSourceOfTruthARoomThatComesBackWithoutARoleLosesTheOneKept() async {
        let store = MemoryRoleStore(["room-a": "training", "room-b": "customer"])
        let repo = repository(store: store)
        RolesServer.set([("room-a", nil), ("room-b", "customer")])
        _ = await repo.refreshRooms()
        XCTAssertEqual(repo.roomRoles, ["room-b": "customer"])
        XCTAssertEqual(store.saved, ["room-b": "customer"])
    }

    func testTheServerIsTheSourceOfTruthAChangedRoleReplacesTheOldOne() async {
        let repo = repository(store: MemoryRoleStore(["room-a": "customer"]))
        RolesServer.set([("room-a", "training")])
        _ = await repo.refreshRooms()
        XCTAssertEqual(repo.roomRoles, ["room-a": "training"])
    }

    func testABlankRoleFromTheServerAlsoClearsTheOneKept() async {
        let repo = repository(store: MemoryRoleStore(["room-a": "training"]))
        RolesServer.set([("room-a", "  ")])
        _ = await repo.refreshRooms()
        XCTAssertEqual(repo.roomRoles, [:])
    }

    func testNothingIsWrittenWhenNothingChanged() async {
        RolesServer.set([("room-a", "training")])
        let store = MemoryRoleStore()
        let repo = repository(store: store)
        _ = await repo.refreshRooms()
        _ = await repo.refreshRooms()
        XCTAssertEqual(store.saves, 1)
    }

    // MARK: the role this device sent when it created a room, until the server says otherwise

    func testARoomThisDeviceJustCreatedShowsItsRoleBeforeTheServerListsIt() {
        let repo = repository()
        repo.rememberLocalRole(roomId: "room-new", role: "training")
        XCTAssertEqual(repo.roomRoles, ["room-new": "training"])
    }

    func testTheLocalRoleIsTrimmedAndABlankOrMissingOneIsIgnored() {
        let repo = repository()
        repo.rememberLocalRole(roomId: "room-a", role: "  training ")
        repo.rememberLocalRole(roomId: "room-b", role: "  ")
        repo.rememberLocalRole(roomId: "room-c", role: nil)
        XCTAssertEqual(repo.roomRoles, ["room-a": "training"])
    }

    func testAServerRoleBeatsTheLocalOne() async {
        let repo = repository()
        repo.rememberLocalRole(roomId: "room-a", role: "customer")
        RolesServer.set([("room-a", "training")])
        _ = await repo.refreshRooms()
        XCTAssertEqual(repo.roomRoles, ["room-a": "training"])
    }

    func testARoomTheServerReturnsWithoutARoleKeepsTheLocalOne() async {
        let repo = repository()
        repo.rememberLocalRole(roomId: "room-a", role: "training")
        RolesServer.set([("room-a", nil)])
        _ = await repo.refreshRooms()
        XCTAssertEqual(repo.roomRoles, ["room-a": "training"])
    }

    func testARoomTheServerDoesNotListYetKeepsTheLocalOne() async {
        let repo = repository()
        repo.rememberLocalRole(roomId: "room-new", role: "training")
        RolesServer.set([("room-old", "customer")])
        _ = await repo.refreshRooms()
        XCTAssertEqual(repo.roomRoles, ["room-new": "training", "room-old": "customer"])
    }

    func testOnceTheServerHasARoleForARoomALaterLocalRoleDoesNotOverrideIt() async {
        let repo = repository()
        RolesServer.set([("room-a", "customer")])
        _ = await repo.refreshRooms()
        repo.rememberLocalRole(roomId: "room-a", role: "training")
        XCTAssertEqual(repo.roomRoles, ["room-a": "customer"])
    }

    func testLocalRolesAreSavedAndComeBackBeforeTheNextFetch() {
        let store = MemoryRoleStore()
        repository(store: store).rememberLocalRole(roomId: "room-new", role: "training")
        XCTAssertEqual(store.savedLocal, ["room-new": "training"])

        let reopened = repository(store: store) // a new launch, offline: nothing fetched yet
        XCTAssertEqual(reopened.roomRoles, ["room-new": "training"])
    }

    func testALocalRoleIsDroppedFromTheStoreOnceTheServerHasTakenOver() async {
        let store = MemoryRoleStore()
        let repo = repository(store: store)
        repo.rememberLocalRole(roomId: "room-a", role: "training")
        RolesServer.set([("room-a", "training")])
        _ = await repo.refreshRooms()
        XCTAssertEqual(store.savedLocal, [:])
        XCTAssertEqual(store.saved, ["room-a": "training"])
    }

    func testTheUserDefaultsStoreRoundTripsPerBot() {
        let suite = UserDefaults(suiteName: "RoomRolesTests-\(UUID().uuidString)")!
        let store = UserDefaultsRoomRoleStore(defaults: suite)
        XCTAssertEqual(store.load(botId: "bot-1"), [:])
        store.save(botId: "bot-1", roles: ["room-a": "training"])
        XCTAssertEqual(store.load(botId: "bot-1"), ["room-a": "training"])
        XCTAssertEqual(store.load(botId: "bot-2"), [:])

        XCTAssertEqual(store.loadLocal(botId: "bot-1"), [:])
        store.saveLocal(botId: "bot-1", roles: ["room-b": "customer"])
        XCTAssertEqual(store.loadLocal(botId: "bot-1"), ["room-b": "customer"])
        XCTAssertEqual(store.load(botId: "bot-1"), ["room-a": "training"], "local roles are kept apart from the server's")
    }
}
