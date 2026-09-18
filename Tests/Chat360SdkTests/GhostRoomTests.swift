import XCTest
import SQLite3
@testable import Chat360SDK

/// Regression test for ghost rooms: every session-init the app makes allocates a real room on
/// the server, and "New chat" used to make one per tap even when the previous new chat was still
/// empty. Scenario from the bug report: open the SDK (room 1, nothing sent), open another room,
/// then tap "New chat" twice - that must land back on room 1 instead of creating rooms 2 and 3.
/// Runs the real `ChatViewModel` + `ChatRepository` against a stubbed URLSession that counts
/// session-init calls.
@MainActor
final class GhostRoomTests: XCTestCase {

    /// Answers session-init like the backend: a known room_id resumes, otherwise a new room is allocated.
    private final class StubServer: URLProtocol {
        static let lock = NSLock()
        static var sessionRequests: [String?] = []
        static var roomCounter = 0

        static func reset() { lock.lock(); sessionRequests = []; roomCounter = 0; lock.unlock() }
        static var requests: [String?] { lock.lock(); defer { lock.unlock() }; return sessionRequests }

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func stopLoading() {}

        override func startLoading() {
            let url = request.url!
            var status = 404
            var body = Data()
            if url.path.contains("/session/") {
                let requested = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "room_id" }?.value
                Self.lock.lock()
                Self.sessionRequests.append(requested)
                Self.roomCounter += 1
                let room = requested ?? "room-\(Self.roomCounter)"
                Self.lock.unlock()
                status = 200
                body = #"{"room_id":"\#(room)","owner_id":"owner-1","session_token":"tok-\#(room)","nodeType":"INIT","targetId":"t1"}"#.data(using: .utf8)!
            }
            let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    private final class InMemorySessionStore: SessionStore {
        private var rooms: [String: PersistedSession] = [:]
        private var last: PersistedSession?
        func load(botId: String) -> PersistedSession? { last }
        func loadForRoom(botId: String, roomId: String) -> PersistedSession? { rooms[roomId] }
        func save(botId: String, session: PersistedSession) { rooms[session.roomId] = session; last = session }
    }

    private let botId = "ghost-room-bot-\(UUID().uuidString)"
    private var dao: ChatCacheDao!
    private var sessionStore: InMemorySessionStore!
    private var viewModel: ChatViewModel!

    override func setUp() async throws {
        StubServer.reset()
        var handle: OpaquePointer?
        sqlite3_open(":memory:", &handle)
        dao = ChatCacheDao(db: handle!)
        sessionStore = InMemorySessionStore()
        viewModel = makeViewModel()
    }

    /// A fresh view model over the same cache/session store - what reopening the chat screen builds.
    private func makeViewModel() -> ChatViewModel {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubServer.self]
        let baseUrl = "https://ghost.test"
        let repository = ChatRepository(
            baseUrl: baseUrl,
            botId: botId,
            apiService: Chat360ApiService(baseUrl: baseUrl, session: URLSession(configuration: configuration)),
            sessionStore: sessionStore
        )
        return ChatViewModel(repository: repository, botId: botId, cache: ChatCacheRepository(dao: dao))
    }

    override func tearDown() async throws {
        viewModel.onCleared()
        viewModel = nil
    }

    private func awaitUntil(_ what: String, timeout: TimeInterval = 8, _ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline { return XCTFail("Timed out waiting for: \(what) (session requests=\(StubServer.requests))") }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    private func settle() async { try? await Task.sleep(nanoseconds: 500_000_000) }

    func testTappingNewChatRepeatedlyAfterVisitingAnotherRoomReusesTheBlankRoom() async {
        // 1. Opening the SDK creates room 1 (the "first screen"); the user sends nothing.
        await awaitUntil("initial room") { StubServer.requests.count == 1 && self.viewModel.uiState.activeConversationId != nil }
        let firstScreenId = viewModel.uiState.activeConversationId
        XCTAssertNotNil(firstScreenId)

        // 2. The user opens a different, older room this device has connected to before.
        sessionStore.save(botId: botId, session: PersistedSession(roomId: "room-old", sessionToken: "tok-room-old", ownerId: "owner-1"))
        await dao.upsertConversation(CachedConversationEntity(id: "conv-old", botId: botId, roomId: "room-old", title: "Old chat", createdAt: 1, updatedAt: 1))
        await awaitUntil("old conversation listed") { self.viewModel.conversations.contains { $0.id == "conv-old" } }
        viewModel.openConversation("conv-old")
        await awaitUntil("old room resumed") { StubServer.requests.contains("room-old") }
        await settle()

        // 3. New chat, twice. Neither may ask the server for a new room.
        viewModel.startNewChat()
        await awaitUntil("blank room resumed") { StubServer.requests.contains("room-1") }
        await settle()
        viewModel.startNewChat()
        await settle()

        let freshRooms = StubServer.requests.filter { $0 == nil }.count
        XCTAssertEqual(freshRooms, 1, "ghost rooms were created: \(StubServer.requests)")
        XCTAssertEqual(viewModel.uiState.activeConversationId, firstScreenId, "New chat must show the original first screen again")
    }

    func testReopeningTheChatScreenInTheSameProcessReusesTheBlankRoom() async {
        await awaitUntil("initial room") { StubServer.requests.count == 1 && self.viewModel.uiState.activeConversationId != nil }
        viewModel.onCleared()

        // The host closes and reopens the chat screen while the app is still running.
        viewModel = makeViewModel()
        await awaitUntil("second open") { StubServer.requests.count >= 2 }
        await settle()

        XCTAssertEqual(StubServer.requests.filter { $0 == nil }.count, 1, "reopening created a ghost room: \(StubServer.requests)")
        XCTAssertEqual(StubServer.requests.last ?? nil, "room-1", "reopening should resume the untouched room")
    }

    func testUnsentTextStaysWithTheRoomItWasTypedIn() async {
        await awaitUntil("initial room") { StubServer.requests.count == 1 && self.viewModel.uiState.activeConversationId != nil }
        viewModel.onInputChange("half typed in the first room")

        sessionStore.save(botId: botId, session: PersistedSession(roomId: "room-old", sessionToken: "tok-room-old", ownerId: "owner-1"))
        await dao.upsertConversation(CachedConversationEntity(id: "conv-old", botId: botId, roomId: "room-old", title: "Old chat", createdAt: 1, updatedAt: 1))
        await awaitUntil("old conversation listed") { self.viewModel.conversations.contains { $0.id == "conv-old" } }
        viewModel.openConversation("conv-old")
        await awaitUntil("old room resumed") { StubServer.requests.contains("room-old") }
        await settle()
        XCTAssertEqual(viewModel.uiState.inputText, "", "the other room must not inherit the text")

        viewModel.onInputChange("typed in the old room")
        viewModel.startNewChat()
        await settle()
        XCTAssertEqual(viewModel.uiState.inputText, "half typed in the first room", "returning restores that room's own text")

        viewModel.openConversation("conv-old")
        await settle()
        XCTAssertEqual(viewModel.uiState.inputText, "typed in the old room")
    }

    // MARK: - Overlapping room loads

    private func seedCachedConversation(_ id: String, roomId: String, texts: [String]) async {
        await dao.upsertConversation(CachedConversationEntity(id: id, botId: botId, roomId: roomId, title: id, createdAt: 1, updatedAt: 1))
        for (index, text) in texts.enumerated() {
            await dao.insertMessage(CachedMessageEntity(conversationId: id, kind: "USER", payload: text, createdAt: Int64(10 + index)))
        }
    }

    private func transcript() -> [String] { viewModel.uiState.messages.map { $0.text } }

    /// Each replay clears the transcript, awaits the cache, then appends. Two overlapping ones both
    /// cleared before either appended, so both appended: two conversations mixed into one screen.
    func testRapidRoomSwitchesNeverMixTwoConversationsIntoOneTranscript() async {
        await awaitUntil("initial room") { StubServer.requests.count == 1 && self.viewModel.uiState.activeConversationId != nil }
        await seedCachedConversation("conv-a", roomId: "room-a", texts: ["a1", "a2"])
        await seedCachedConversation("conv-b", roomId: "room-b", texts: ["b1", "b2"])
        await awaitUntil("conversations listed") { self.viewModel.conversations.contains { $0.id == "conv-a" } && self.viewModel.conversations.contains { $0.id == "conv-b" } }

        viewModel.openConversation("conv-a")
        viewModel.openConversation("conv-b")
        await settle()
        XCTAssertEqual(transcript(), ["b1", "b2"], "the transcript mixed the two conversations")

        // A -> B -> A: the stale first visit to A used to look current again once the last hop made A active.
        viewModel.openConversation("conv-a")
        viewModel.openConversation("conv-b")
        viewModel.openConversation("conv-a")
        await settle()
        XCTAssertEqual(transcript(), ["a1", "a2"], "a stale visit to A wrote into the transcript")
    }

    func testTheLastRoomOpenedWinsHoweverManyAreOpenedInARow() async {
        await awaitUntil("initial room") { StubServer.requests.count == 1 && self.viewModel.uiState.activeConversationId != nil }
        await seedCachedConversation("conv-a", roomId: "room-a", texts: ["a1"])
        await seedCachedConversation("conv-b", roomId: "room-b", texts: ["b1", "b2"])
        await seedCachedConversation("conv-c", roomId: "room-c", texts: ["c1", "c2", "c3"])
        await awaitUntil("conversations listed") { self.viewModel.conversations.count >= 3 }

        for id in ["conv-a", "conv-b", "conv-c", "conv-a", "conv-c"] { viewModel.openConversation(id) }
        await settle()

        XCTAssertEqual(transcript(), ["c1", "c2", "c3"])
        XCTAssertEqual(viewModel.uiState.activeConversationId, "conv-c")
    }
}
