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
        /// Server-configured welcome copy: what the stub returns, and the client_id header of every request.
        static var welcomeStatus = 200
        static var welcomeBody = #"{"heading":"Server heading","text":"Server subtitle","client_id":"client-1"}"#
        static var welcomeDelay: TimeInterval = 0
        static var welcomeClientIds: [String?] = []
        static var welcomeRequests: [String?] { lock.lock(); defer { lock.unlock() }; return welcomeClientIds }

        /// The sales-executive check and the maintenance flag: what each returns, and what the app sent.
        static let activeExecutive = #"{"success":true,"message":"Sales Executive validated successfully.","is_new":false,"status_downgraded_to_inactive":false,"sales_executive":{"id":12,"emp_code":"EMP1101","name":"","role":"Trainer","dealer_code":"W4300","dealer_name":"Hindustan Hyundai","status":"ACTIVE"}}"#
        static let inactiveExecutive = #"{"success":true,"message":"Sales Executive onboarded as INACTIVE.","is_new":true,"status_downgraded_to_inactive":false,"sales_executive":{"id":12,"emp_code":"EMP1101","name":"","role":null,"dealer_code":"W4300","dealer_name":"Hindustan Hyundai","status":"INACTIVE"}}"#
        static var salesStatus = 200
        static var salesBody = activeExecutive
        static var salesDelay: TimeInterval = 0
        static var salesClientIds: [String?] = []
        static var salesBodies: [String] = []
        static var salesRequestCount: Int { lock.lock(); defer { lock.unlock() }; return salesClientIds.count }
        static var maintenanceBody = #"{"is_active":false}"#

        /// History fetches per room, and how many of the room under test's fetches see no bot reply yet.
        static var historyRequestsByRoom: [String: Int] = [:]
        static var historyWithoutReply = 0
        /// The room whose history the reply tests are about; every other room's history never has a reply.
        static let roomUnderTest = "room-a"

        static func reset() {
            lock.lock(); sessionRequests = []; roomCounter = 0; historyRequestsByRoom = [:]; historyWithoutReply = 0
            salesStatus = 200; salesBody = activeExecutive; salesDelay = 0; salesClientIds = []; salesBodies = []; maintenanceBody = #"{"is_active":false}"#
            welcomeStatus = 200; welcomeBody = #"{"heading":"Server heading","text":"Server subtitle","client_id":"client-1"}"#; welcomeDelay = 0; welcomeClientIds = []
            lock.unlock()
        }
        static var historyFetches: Int { lock.lock(); defer { lock.unlock() }; return historyRequestsByRoom[roomUnderTest] ?? 0 }

        /// A history page: the user's message, plus the bot's reply once enough fetches have gone by.
        static func historyBody(includeReply: Bool) -> Data {
            let user = RawSocketEnvelope(user: "end_user", message: .string("Tell me about Hyundai Venue features"), chat_msg_id: "user-1")
            let bot = RawSocketEnvelope(user: "bot", data: .object(["nodeType": .string("TEXT"), "id": .string("reply-1"), "questionText": .string("Venue features reply")]), timestamp_int: String(Int(Date().timeIntervalSince1970)))
            let rows = ([user] + (includeReply ? [bot] : [])).compactMap { try? String(data: JSONEncoder().encode($0), encoding: .utf8) }
            return Data(#"{"history":[\#(rows.joined(separator: ","))],"previous_cursor":null}"#.utf8)
        }
        static var requests: [String?] { lock.lock(); defer { lock.unlock() }; return sessionRequests }

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func stopLoading() {}

        override func startLoading() {
            let url = request.url!
            var status = 404
            var body = Data()
            if url.path.hasSuffix("/api/third-party-tasks/sales-exectives") {
                var sent = request.httpBody ?? Data()
                if sent.isEmpty, let stream = request.httpBodyStream {
                    stream.open(); defer { stream.close() }
                    var buffer = [UInt8](repeating: 0, count: 4096)
                    while stream.hasBytesAvailable { let n = stream.read(&buffer, maxLength: buffer.count); if n <= 0 { break }; sent.append(buffer, count: n) }
                }
                Self.lock.lock()
                Self.salesClientIds.append(request.value(forHTTPHeaderField: "Client-Id"))
                Self.salesBodies.append(String(decoding: sent, as: UTF8.self))
                status = Self.salesStatus
                body = Data(Self.salesBody.utf8)
                let delay = Self.salesDelay
                Self.lock.unlock()
                if delay > 0 { Thread.sleep(forTimeInterval: delay) }
            } else if url.path.hasSuffix("/api/third-party-tasks/maintainance") {
                Self.lock.lock(); body = Data(Self.maintenanceBody.utf8); Self.lock.unlock()
                status = 200
            } else if url.path.hasSuffix("/api/third-party-tasks/welcome-text") {
                Self.lock.lock()
                Self.welcomeClientIds.append(request.value(forHTTPHeaderField: "Client-Id"))
                status = Self.welcomeStatus
                body = Data(Self.welcomeBody.utf8)
                let delay = Self.welcomeDelay
                Self.lock.unlock()
                if delay > 0 { Thread.sleep(forTimeInterval: delay) }
            } else if url.path.contains("/chatbox/messages/") {
                let room = url.lastPathComponent
                Self.lock.lock()
                Self.historyRequestsByRoom[room, default: 0] += 1
                let includeReply = room == Self.roomUnderTest && Self.historyRequestsByRoom[room, default: 0] > Self.historyWithoutReply
                Self.lock.unlock()
                status = 200
                body = Self.historyBody(includeReply: includeReply)
            } else if url.path.contains("/session/") {
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
    private func makeViewModel(welcome: WelcomeTextRepository? = nil, gate: SalesExecutiveGate? = nil, maintenanceApi: ThirdPartyTasksApiService? = nil) -> ChatViewModel {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubServer.self]
        let baseUrl = "https://ghost.test"
        let repository = ChatRepository(
            baseUrl: baseUrl,
            botId: botId,
            apiService: Chat360ApiService(baseUrl: baseUrl, session: URLSession(configuration: configuration)),
            sessionStore: sessionStore
        )
        return ChatViewModel(repository: repository, botId: botId, cache: ChatCacheRepository(dao: dao), maintenanceApi: maintenanceApi, welcomeTextRepository: welcome, salesExecutiveGate: gate)
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

    // MARK: - An older room this device has no saved session for
    // A room only ever seen in the rooms list (another device, a reinstall) can't be resumed through the
    // session endpoint - it ignores the room id and allocates a different room. Like the web widget, the socket
    // joins the room directly instead, so chatting in it continues that same room rather than starting a new one.

    private func seedOtherDeviceRoom() async {
        await dao.upsertConversation(CachedConversationEntity(id: "conv-other", botId: botId, roomId: "room-other", title: "From elsewhere", createdAt: 1, updatedAt: 1))
        await awaitUntil("conversation listed") { self.viewModel.conversations.contains { $0.id == "conv-other" } }
    }

    func testSendingFromARoomWithNoSavedSessionStaysInThatRoomAndCreatesNoNewOne() async {
        await awaitUntil("initial room") { StubServer.requests.count == 1 && self.viewModel.uiState.activeConversationId != nil }
        let connectedConversationId = viewModel.uiState.activeConversationId!
        let before = StubServer.requests.count
        await seedOtherDeviceRoom()

        viewModel.openConversation("conv-other")
        await settle()
        XCTAssertFalse(viewModel.uiState.needsNewSession, "joining the room must not be treated as needing a new session")

        let text = "hello from the old room"
        viewModel.onInputChange(text)
        viewModel.sendMessage()

        await awaitUntil("the text to appear in the old room's transcript", timeout: 8) { self.transcript().contains(text) }
        await settle()
        XCTAssertEqual(StubServer.requests.count, before, "a new room was created: \(StubServer.requests)")
        let cachedInConnectedRoom = await dao.messages(conversationId: connectedConversationId).map { $0.payload }
        XCTAssertFalse(cachedInConnectedRoom.contains(text), "the text was filed under the room that was connected before")
        let cachedInOldRoom = await dao.messages(conversationId: "conv-other").map { $0.payload }
        XCTAssertTrue(cachedInOldRoom.contains(text), "the text was not filed under the old room it was typed in")
    }

    func testMovingBetweenARoomJoinedDirectlyAndAResumableRoomNeverAsksForANewSession() async {
        await awaitUntil("initial room") { StubServer.requests.count == 1 && self.viewModel.uiState.activeConversationId != nil }
        await seedOtherDeviceRoom()
        viewModel.openConversation("conv-other")
        await settle()
        XCTAssertFalse(viewModel.uiState.needsNewSession)

        sessionStore.save(botId: botId, session: PersistedSession(roomId: "room-old", sessionToken: "tok-room-old", ownerId: "owner-1"))
        await dao.upsertConversation(CachedConversationEntity(id: "conv-old", botId: botId, roomId: "room-old", title: "Old chat", createdAt: 1, updatedAt: 1))
        await awaitUntil("old conversation listed") { self.viewModel.conversations.contains { $0.id == "conv-old" } }
        viewModel.openConversation("conv-old")
        await awaitUntil("old room resumed") { StubServer.requests.contains("room-old") }
        await settle()
        XCTAssertFalse(viewModel.uiState.needsNewSession)

        viewModel.openConversation("conv-other")
        await settle()
        XCTAssertFalse(viewModel.uiState.needsNewSession)
        XCTAssertEqual(StubServer.requests.filter { $0 == nil }.count, 1, "a room was created along the way: \(StubServer.requests)")
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

    // MARK: - A reply generated while away

    /// The server stores a reply ~14s after the send whether or not a socket is connected, but only pushes
    /// it to a socket connected to that room at that moment. Returning sooner found nothing on the one
    /// history check and nothing ever looked again.
    private func seedPendingConversation(_ id: String, roomId: String, pendingSinceMsAgo: Int64 = 0) async {
        await seedCachedConversation(id, roomId: roomId, texts: ["Tell me about Hyundai Venue features"])
        await dao.markReplyPending(conversationId: id, chatMsgId: "user-1", createdAt: Int64(Date().timeIntervalSince1970 * 1000) - pendingSinceMsAgo)
    }

    func testAReplyStoredAfterTheFirstCheckOnReturnStillAppears() async {
        ChatViewModel.missedReplyPollIntervalNs = 50_000_000
        defer { ChatViewModel.missedReplyPollIntervalNs = 3_000_000_000 }
        StubServer.historyWithoutReply = 2 // the first two checks find only the user's message
        await awaitUntil("initial room") { StubServer.requests.count == 1 && self.viewModel.uiState.activeConversationId != nil }
        await seedPendingConversation("conv-a", roomId: "room-a")
        await awaitUntil("conversation listed") { self.viewModel.conversations.contains { $0.id == "conv-a" } }

        viewModel.openConversation("conv-a")

        await awaitUntil("the reply to appear") { self.transcript().contains("Venue features reply") }
        XCTAssertGreaterThanOrEqual(StubServer.historyFetches, 3, "it never looked again after the first check")
        XCTAssertFalse(viewModel.uiState.isAgentTyping, "the typing indicator was left on after the reply arrived")
    }

    func testPollingStopsOnceTheReplyHasBeenFound() async {
        ChatViewModel.missedReplyPollIntervalNs = 50_000_000
        defer { ChatViewModel.missedReplyPollIntervalNs = 3_000_000_000 }
        StubServer.historyWithoutReply = 1
        await awaitUntil("initial room") { StubServer.requests.count == 1 && self.viewModel.uiState.activeConversationId != nil }
        await seedPendingConversation("conv-a", roomId: "room-a")
        await awaitUntil("conversation listed") { self.viewModel.conversations.contains { $0.id == "conv-a" } }

        viewModel.openConversation("conv-a")
        await awaitUntil("the reply to appear") { self.transcript().contains("Venue features reply") }
        await settle()
        let fetchesOnceFound = StubServer.historyFetches
        await settle()

        XCTAssertEqual(StubServer.historyFetches, fetchesOnceFound, "kept polling after the reply was found")
    }

    func testAMessageThatIsAlreadyStaleIsMarkedUndeliveredAndNotPolledForever() async {
        ChatViewModel.missedReplyPollIntervalNs = 50_000_000
        defer { ChatViewModel.missedReplyPollIntervalNs = 3_000_000_000 }
        StubServer.historyWithoutReply = 1_000_000 // the reply never shows up
        await awaitUntil("initial room") { StubServer.requests.count == 1 && self.viewModel.uiState.activeConversationId != nil }
        await seedPendingConversation("conv-a", roomId: "room-a", pendingSinceMsAgo: 200_000) // older than the 90s give-up point
        await awaitUntil("conversation listed") { self.viewModel.conversations.contains { $0.id == "conv-a" } }

        viewModel.openConversation("conv-a")
        await settle()
        let fetches = StubServer.historyFetches
        await settle()

        XCTAssertEqual(StubServer.historyFetches, fetches, "polled forever for a reply that was given up on")
        XCTAssertFalse(viewModel.uiState.isAgentTyping)
    }

    func testPollingStopsWhenTheUserMovesToAnotherRoom() async {
        ChatViewModel.missedReplyPollIntervalNs = 50_000_000
        defer { ChatViewModel.missedReplyPollIntervalNs = 3_000_000_000 }
        StubServer.historyWithoutReply = 1_000_000
        await awaitUntil("initial room") { StubServer.requests.count == 1 && self.viewModel.uiState.activeConversationId != nil }
        await seedPendingConversation("conv-a", roomId: "room-a")
        await seedCachedConversation("conv-b", roomId: "room-b", texts: ["b1"])
        await awaitUntil("conversations listed") { self.viewModel.conversations.contains { $0.id == "conv-a" } && self.viewModel.conversations.contains { $0.id == "conv-b" } }

        viewModel.openConversation("conv-a")
        await awaitUntil("polling under way") { StubServer.historyFetches >= 3 }
        viewModel.openConversation("conv-b")
        await settle()
        let fetches = StubServer.historyFetches
        await settle()

        XCTAssertEqual(StubServer.historyFetches, fetches, "kept polling room A after the user left it")
        XCTAssertEqual(transcript(), ["b1"])
    }

    func testAReplyThatArrivesLiveEndsThePolling() async {
        ChatViewModel.missedReplyPollIntervalNs = 50_000_000
        defer { ChatViewModel.missedReplyPollIntervalNs = 3_000_000_000 }
        StubServer.historyWithoutReply = 1_000_000
        await awaitUntil("initial room") { StubServer.requests.count == 1 && self.viewModel.uiState.activeConversationId != nil }
        await seedPendingConversation("conv-a", roomId: "room-a")
        await awaitUntil("conversation listed") { self.viewModel.conversations.contains { $0.id == "conv-a" } }

        viewModel.openConversation("conv-a")
        await awaitUntil("polling under way") { StubServer.historyFetches >= 3 }
        await dao.clearReplyPending(conversationId: "conv-a") // what a live frame delivering the reply does
        await settle()
        let fetches = StubServer.historyFetches
        await settle()

        XCTAssertEqual(StubServer.historyFetches, fetches, "kept polling after a live reply cleared the pending record")
    }

    // MARK: - Server-configured welcome text

    private final class MemoryWelcomeStore: WelcomeTextStore {
        var saved: WelcomeText?
        init(_ saved: WelcomeText? = nil) { self.saved = saved }
        func load(clientId: String) -> WelcomeText? { saved }
        func save(clientId: String, welcomeText: WelcomeText?) { saved = welcomeText }
    }

    private func welcomeRepository(_ store: WelcomeTextStore = MemoryWelcomeStore()) -> WelcomeTextRepository {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubServer.self]
        let api = ThirdPartyTasksApiService(baseUrl: "https://ghost.test", session: URLSession(configuration: configuration))
        return WelcomeTextRepository(apiService: api, clientId: "client-1", store: store)
    }

    func testTheServersWelcomeTextReachesTheScreenStateAskedForWithTheClientId() async {
        viewModel = makeViewModel(welcome: welcomeRepository())

        await awaitUntil("the welcome text to load") { self.viewModel.uiState.welcomeOverride != nil }

        XCTAssertEqual(viewModel.uiState.welcomeOverride, WelcomeText(heading: "Server heading", text: "Server subtitle"))
        XCTAssertEqual(StubServer.welcomeRequests, ["client-1"])
    }

    func testTheCachedWelcomeTextIsThereImmediatelyBeforeTheServerHasAnswered() async {
        StubServer.welcomeDelay = 1.5
        viewModel = makeViewModel(welcome: welcomeRepository(MemoryWelcomeStore(WelcomeText(heading: "Cached heading", text: "Cached subtitle"))))

        // No waiting: this is the very first paint.
        XCTAssertEqual(viewModel.uiState.welcomeOverride, WelcomeText(heading: "Cached heading", text: "Cached subtitle"))

        await awaitUntil("the fresh text to replace it") { self.viewModel.uiState.welcomeOverride?.heading == "Server heading" }
    }

    func testAnEndpointThatIsNotDeployedLeavesTheDefaultsAndDoesNotGetInTheChatsWay() async {
        StubServer.welcomeStatus = 404
        StubServer.welcomeBody = "<!DOCTYPE html><html>Page not found</html>"
        viewModel = makeViewModel(welcome: welcomeRepository())

        await awaitUntil("the welcome request") { !StubServer.welcomeRequests.isEmpty }
        await settle()

        XCTAssertNil(viewModel.uiState.welcomeOverride)
        await awaitUntil("the chat to connect regardless") { StubServer.requests.count >= 2 && self.viewModel.uiState.activeConversationId != nil }
    }

    func testAFailureKeepsAPreviouslyCachedWelcomeTextOnScreen() async {
        StubServer.welcomeStatus = 500
        viewModel = makeViewModel(welcome: welcomeRepository(MemoryWelcomeStore(WelcomeText(heading: "Cached heading", text: "Cached subtitle"))))

        await awaitUntil("the welcome request") { !StubServer.welcomeRequests.isEmpty }
        await settle()

        XCTAssertEqual(viewModel.uiState.welcomeOverride, WelcomeText(heading: "Cached heading", text: "Cached subtitle"))
    }

    func testTheServerClearingItsWelcomeTextRemovesTheOverride() async {
        StubServer.welcomeBody = #"{"heading":"","text":""}"#
        viewModel = makeViewModel(welcome: welcomeRepository(MemoryWelcomeStore(WelcomeText(heading: "Old heading", text: "Old subtitle"))))

        await awaitUntil("the empty reply to clear it") { self.viewModel.uiState.welcomeOverride == nil }
    }

    func testAHostWithoutAClientIdNeverAsksTheServer() async {
        viewModel = makeViewModel(welcome: nil)
        await awaitUntil("the chat to connect") { self.viewModel.uiState.activeConversationId != nil }
        await settle()

        XCTAssertTrue(StubServer.welcomeRequests.isEmpty, "asked anyway: \(StubServer.welcomeRequests)")
        XCTAssertNil(viewModel.uiState.welcomeOverride)
    }

    // MARK: - Sales-executive gate
    // Closed like maintenance: no socket, the server's message in place of the input bar. Anything other than a
    // clear INACTIVE lets the chat run untouched.

    private func stubbedApi() -> ThirdPartyTasksApiService {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubServer.self]
        return ThirdPartyTasksApiService(baseUrl: "https://ghost.test", session: URLSession(configuration: configuration))
    }

    private func gate(timeout: TimeInterval = 3) -> SalesExecutiveGate {
        SalesExecutiveGate(apiService: stubbedApi(), clientId: "client-1", details: ["dealer_code": "W4300", "emp_code": "EMP1101"], timeout: timeout)
    }

    /// A view model started fresh with the gate, plus how many rooms had already been created before it.
    private func startGated(_ gate: SalesExecutiveGate?, maintenanceApi: ThirdPartyTasksApiService? = nil) async -> Int {
        await awaitUntil("the harness's own room") { StubServer.requests.count == 1 }
        let before = StubServer.requests.count
        viewModel = makeViewModel(gate: gate, maintenanceApi: maintenanceApi)
        return before
    }

    func testAnInactiveExecutiveGetsTheServersMessageAndNoSocketIsEverOpened() async {
        StubServer.salesBody = StubServer.inactiveExecutive
        let before = await startGated(gate())

        await awaitUntil("the block to show") { self.viewModel.uiState.terminalFallbackMessage != nil }
        await settle()

        XCTAssertEqual(viewModel.uiState.terminalFallbackMessage, "Sales Executive onboarded as INACTIVE.")
        XCTAssertEqual(StubServer.requests.count, before, "a room was created for a blocked executive: \(StubServer.requests)")
        XCTAssertEqual(StubServer.salesClientIds, ["client-1"])
        XCTAssertTrue(StubServer.salesBodies.first?.contains("\"emp_code\":\"EMP1101\"") == true)
    }

    func testAnActiveExecutiveConnectsNormallyWithNoBlock() async {
        let before = await startGated(gate())

        await awaitUntil("the chat to connect") { StubServer.requests.count == before + 1 }

        XCTAssertNil(viewModel.uiState.terminalFallbackMessage)
    }

    func testAFailingCheckNeverBlocksErrorsAnUndeployedEndpointAndAMalformedReplyAllLetTheChatConnect() async {
        for (status, body) in [(500, ""), (404, "<html>Page not found</html>"), (400, #"{"success":false,"errors":{"emp_code":["This field is required."]}}"#), (200, "<html>proxy</html>")] {
            StubServer.salesStatus = status
            StubServer.salesBody = body
            let before = max(StubServer.requests.count, 1)
            viewModel = makeViewModel(gate: gate())

            await awaitUntil("the chat to connect despite HTTP \(status)") { StubServer.requests.count > before }
            XCTAssertNil(viewModel.uiState.terminalFallbackMessage, "blocked on HTTP \(status)")
        }
    }

    func testASlowServerDoesNotHoldTheChatBack() async {
        StubServer.salesBody = StubServer.inactiveExecutive
        StubServer.salesDelay = 4 // answers far too late
        let before = await startGated(gate(timeout: 0.4))

        await awaitUntil("the chat to connect without waiting for the check") { StubServer.requests.count == before + 1 }

        XCTAssertNil(viewModel.uiState.terminalFallbackMessage)
    }

    func testOnceTheExecutiveIsActivatedReturningToTheAppStartsTheChatThatWasNeverOpened() async {
        StubServer.salesBody = StubServer.inactiveExecutive
        let before = await startGated(gate())
        await awaitUntil("the block to show") { self.viewModel.uiState.terminalFallbackMessage != nil }
        XCTAssertEqual(StubServer.requests.count, before)

        StubServer.salesBody = StubServer.activeExecutive // an admin activates them
        viewModel.onAppForegrounded()

        await awaitUntil("the chat to start") { StubServer.requests.count == before + 1 }
        await awaitUntil("the block to clear") { self.viewModel.uiState.terminalFallbackMessage == nil }
    }

    func testAManualRetryAfterBeingActivatedAlsoStartsTheChat() async {
        StubServer.salesBody = StubServer.inactiveExecutive
        let before = await startGated(gate())
        await awaitUntil("the block to show") { self.viewModel.uiState.terminalFallbackMessage != nil }

        StubServer.salesBody = StubServer.activeExecutive
        viewModel.refreshConnection()

        await awaitUntil("the chat to start") { StubServer.requests.count == before + 1 }
    }

    func testStartingANewChatAfterBeingBlockedAtStartupDoesTheFirstConnectProperly() async {
        StubServer.salesBody = StubServer.inactiveExecutive
        let before = await startGated(gate())
        await awaitUntil("the block to show") { self.viewModel.uiState.terminalFallbackMessage != nil }

        StubServer.salesBody = StubServer.activeExecutive
        viewModel.startNewChat()

        await awaitUntil("the chat to start") { StubServer.requests.count == before + 1 }
        await awaitUntil("the room to be shown") { self.viewModel.uiState.activeConversationId != nil }
        XCTAssertNil(viewModel.uiState.terminalFallbackMessage)
    }

    func testAnExecutiveWhoIsStillInactiveStaysBlockedWhenReturningToTheApp() async {
        StubServer.salesBody = StubServer.inactiveExecutive
        let before = await startGated(gate())
        await awaitUntil("the block to show") { self.viewModel.uiState.terminalFallbackMessage != nil }

        viewModel.onAppForegrounded()
        await settle()

        XCTAssertEqual(viewModel.uiState.terminalFallbackMessage, "Sales Executive onboarded as INACTIVE.")
        XCTAssertEqual(StubServer.requests.count, before)
    }

    func testOnceActiveTheCheckIsNotRepeatedWhenReturningToTheApp() async {
        let before = await startGated(gate())
        await awaitUntil("the chat to connect") { StubServer.requests.count == before + 1 }

        viewModel.onAppForegrounded()
        viewModel.onAppForegrounded()
        await settle()

        XCTAssertEqual(StubServer.salesRequestCount, 1, "re-checked on every foreground")
    }

    func testMaintenanceModeTakesPriorityOverAnInactiveExecutive() async {
        await awaitUntil("the harness's own room") { StubServer.requests.count == 1 } // before maintenance flips on
        StubServer.lock.lock(); StubServer.maintenanceBody = #"{"is_active":true,"message":"Down for maintenance"}"#; StubServer.lock.unlock()
        StubServer.salesBody = StubServer.inactiveExecutive
        let before = await startGated(gate(), maintenanceApi: stubbedApi())

        await awaitUntil("the block to show") { self.viewModel.uiState.terminalFallbackMessage != nil }
        await settle()

        XCTAssertEqual(viewModel.uiState.terminalFallbackMessage, "Down for maintenance")
        XCTAssertEqual(StubServer.requests.count, before)
    }

    func testAHostThatConfiguresNoSalesExecutiveNeverCallsTheEndpoint() async {
        let before = await startGated(nil)

        await awaitUntil("the chat to connect") { StubServer.requests.count == before + 1 }
        await settle()

        XCTAssertEqual(StubServer.salesRequestCount, 0, "asked anyway: \(StubServer.salesClientIds)")
    }
}
