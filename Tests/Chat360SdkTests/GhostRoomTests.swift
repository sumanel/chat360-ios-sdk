import XCTest
import SQLite3
import Combine
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
        /// Every room's history is empty (nothing was ever said) - for tests about what a brand-new chat does by itself.
        static var historyIsEmpty = false
        static var appFeedbackStatus = 200
        static var appFeedbackBodies: [String] = []
        /// The room whose history the reply tests are about; every other room's history never has a reply.
        static let roomUnderTest = "room-a"

        static func reset() {
            lock.lock(); sessionRequests = []; roomCounter = 0; historyRequestsByRoom = [:]; historyWithoutReply = 0; historyIsEmpty = false
            appFeedbackStatus = 200; appFeedbackBodies = []
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
            } else if url.path.hasSuffix("/api/third-party-tasks/app-feedback") {
                var sent = request.httpBody ?? Data()
                if sent.isEmpty, let stream = request.httpBodyStream {
                    stream.open(); defer { stream.close() }
                    var buffer = [UInt8](repeating: 0, count: 4096)
                    while stream.hasBytesAvailable { let n = stream.read(&buffer, maxLength: buffer.count); if n <= 0 { break }; sent.append(buffer, count: n) }
                }
                Self.lock.lock()
                Self.appFeedbackBodies.append(String(decoding: sent, as: UTF8.self))
                status = Self.appFeedbackStatus
                body = Data("{}".utf8)
                Self.lock.unlock()
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
                let empty = Self.historyIsEmpty
                Self.lock.unlock()
                status = 200
                body = empty ? Data(#"{"history":[],"previous_cursor":null}"#.utf8) : Self.historyBody(includeReply: includeReply)
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
        // The repository saves from background tasks while tests save from the test thread, so access is locked.
        private let lock = NSLock()
        private var rooms: [String: PersistedSession] = [:]
        private var last: PersistedSession?
        func load(botId: String) -> PersistedSession? { lock.lock(); defer { lock.unlock() }; return last }
        func loadForRoom(botId: String, roomId: String) -> PersistedSession? { lock.lock(); defer { lock.unlock() }; return rooms[roomId] }
        func save(botId: String, session: PersistedSession) { lock.lock(); defer { lock.unlock() }; rooms[session.roomId] = session; last = session }
    }

    private let botId = "ghost-room-bot-\(UUID().uuidString)"
    private var dao: ChatCacheDao!
    private var sessionStore: InMemorySessionStore!
    private var viewModel: ChatViewModel!
    private var repository: ChatRepository!

    override func setUp() async throws {
        StubServer.reset()
        var handle: OpaquePointer?
        sqlite3_open(":memory:", &handle)
        dao = ChatCacheDao(db: handle!)
        sessionStore = InMemorySessionStore()
        viewModel = makeViewModel()
    }

    /// A fresh view model over the same cache/session store - what reopening the chat screen builds.
    private func makeViewModel(welcome: WelcomeTextRepository? = nil, gate: SalesExecutiveGate? = nil, maintenanceApi: ThirdPartyTasksApiService? = nil, history: ChatHistoryRepository? = nil) -> ChatViewModel {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubServer.self]
        let baseUrl = "https://ghost.test"
        let repository = ChatRepository(
            baseUrl: baseUrl,
            botId: botId,
            apiService: Chat360ApiService(baseUrl: baseUrl, session: URLSession(configuration: configuration)),
            sessionStore: sessionStore
        )
        self.repository = repository
        return ChatViewModel(repository: repository, botId: botId, cache: ChatCacheRepository(dao: dao), chatHistoryRepository: history, maintenanceApi: maintenanceApi, welcomeTextRepository: welcome, salesExecutiveGate: gate, appFeedbackDealerId: "D1", appFeedbackEmpId: "12345")
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

    /// Opening an older room only shows it - the server is not asked for its session until something is sent in it
    /// (see `ChatViewModel.openConversation`). This is that first send, which resumes the room and makes it the connected one.
    private func sendInOpenedRoom(_ room: String, text: String = "hello") async {
        viewModel.onInputChange(text)
        viewModel.sendMessage()
        await awaitUntil("\(room) resumed") { StubServer.requests.contains(room) }
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
        await sendInOpenedRoom("room-old")
        await settle()

        // 3. New chat, twice. Neither may ask the server for a new room.
        viewModel.startNewChat()
        // The send above left a reply outstanding; the repository waits up to 10s for it before switching away.
        await awaitUntil("blank room resumed", timeout: 20) { StubServer.requests.contains("room-1") }
        await settle()
        viewModel.startNewChat()
        await settle()

        let freshRooms = StubServer.requests.filter { $0 == nil }.count
        XCTAssertEqual(freshRooms, 1, "ghost rooms were created: \(StubServer.requests)")
        XCTAssertEqual(viewModel.uiState.activeConversationId, firstScreenId, "New chat must show the original first screen again")
    }

    func testOpeningAnOldRoomDoesNotAskTheServerForItsSessionUntilSomethingIsSent() async {
        await awaitUntil("initial room") { StubServer.requests.count == 1 && self.viewModel.uiState.activeConversationId != nil }
        sessionStore.save(botId: botId, session: PersistedSession(roomId: "room-old", sessionToken: "tok-room-old", ownerId: "owner-1"))
        await dao.upsertConversation(CachedConversationEntity(id: "conv-old", botId: botId, roomId: "room-old", title: "Old chat", createdAt: 1, updatedAt: 1))
        await awaitUntil("old conversation listed") { self.viewModel.conversations.contains { $0.id == "conv-old" } }

        viewModel.openConversation("conv-old")
        await settle()

        // Session-init renews an expired session - a "new session" in the logs and a running timer for a room the
        // user has only looked at.
        XCTAssertEqual(StubServer.requests, [nil], "looking at an old room contacted the server: \(StubServer.requests)")
        XCTAssertEqual(viewModel.uiState.activeConversationId, "conv-old")
        XCTAssertNil(viewModel.uiState.sessionTimerExpiresAt, "no countdown for a room nobody has written to")

        await sendInOpenedRoom("room-old", text: "my first question")

        XCTAssertEqual(StubServer.requests, [nil, "room-old"], "the first send resumes that room, and only that")
    }

    // MARK: - The session timer

    /// The bot's own opening message arrives on connect, before anything has been typed. It used to start the
    /// countdown by itself ("timer is initiating from the SDK").
    func testTheBotsOpeningMessageDoesNotStartTheTimer() async {
        await awaitUntil("initial room") { StubServer.requests.count == 1 && self.viewModel.uiState.activeConversationId != nil }
        // A brand-new chat: the room has no history, so the only thing that can start the timer is what happens now.
        StubServer.historyIsEmpty = true
        viewModel.onCleared()
        viewModel = makeViewModel()
        await awaitUntil("chat reopened on the untouched room") { StubServer.requests.count >= 2 && self.viewModel.uiState.activeConversationId != nil }
        await settle()

        liveReply(from: "room-1") // the welcome message - the user has typed nothing
        await settle()
        XCTAssertTrue(transcript().contains { $0.contains("live-room-1") }, "the welcome message should still show: \(transcript())")
        XCTAssertNil(viewModel.uiState.sessionTimerExpiresAt, "the welcome message started the countdown")

        viewModel.onInputChange("Tell me about the Venue")
        viewModel.sendMessage()
        await settle()
        liveReply(from: "room-1") // the answer
        await settle()

        // The reply alone starts nothing: with no server `updated_at` there is nothing to count from.
        XCTAssertNil(viewModel.uiState.sessionTimerExpiresAt, "the bot's reply started a local countdown with no server anchor")

        // The server's session-time answer (with updated_at) is what starts it.
        repository.handleIncoming(#"{"data_type":"session_time_hyundai","found":true,"session":{"room_id":"room-1","updated_at":"\#(utcStamp(secondsAgo: 0))"}}"#)
        await settle()
        XCTAssertNotNil(viewModel.uiState.sessionTimerExpiresAt, "the server's updated_at should start it once the user has sent")
    }

    func testASessionTimeAnswerWithoutUpdatedAtNeverStartsTheTimer() async {
        await awaitUntil("initial room") { StubServer.requests.count == 1 && self.viewModel.uiState.activeConversationId != nil }
        viewModel.onInputChange("Tell me about the Venue")
        viewModel.sendMessage()
        await settle()
        liveReply(from: "room-1")
        await settle()

        // Only created_at - production and staging send this today.
        repository.handleIncoming(#"{"data_type":"session_time_hyundai","found":true,"session":{"room_id":"room-1","created_at":"\#(utcStamp(secondsAgo: 0))"}}"#)
        await settle()

        XCTAssertNil(viewModel.uiState.sessionTimerExpiresAt, "created_at must not start the timer, and neither may a local clock")
    }

    func testTheServersAnswerBeforeTheUserSendsShowsNothingUntilTheyDo() async {
        await awaitUntil("initial room") { StubServer.requests.count == 1 && self.viewModel.uiState.activeConversationId != nil }
        repository.awaitingSessionTimeResponse = true
        repository.handleIncoming(#"{"data_type":"session_time_hyundai","found":true,"session":{"room_id":"room-1","updated_at":"\#(utcStamp(secondsAgo: 300))"}}"#)
        await settle()
        XCTAssertNil(viewModel.uiState.sessionTimerExpiresAt, "the user has not sent yet")

        viewModel.onInputChange("Tell me about the Venue")
        viewModel.sendMessage()
        await settle()
        liveReply(from: "room-1") // the bot's answer: the stored server anchor now shows
        await settle()

        let remaining = viewModel.uiState.sessionTimerExpiresAt?.timeIntervalSinceNow ?? 0
        XCTAssertTrue((3_200...3_400).contains(remaining), "expected about 55 minutes left from the stored updated_at, got \(remaining)s")
    }

    // MARK: - application-wide feedback (drawer)

    private func makeHistory() -> ChatHistoryRepository {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubServer.self]
        let api = ThirdPartyTasksApiService(baseUrl: "https://ghost.test", session: URLSession(configuration: configuration))
        return ChatHistoryRepository(
            apiService: api,
            tokenManager: ThirdPartyTokenManager(fetchToken: { TokenResponse(bearerToken: "tok-1") }),
            cache: ChatCacheRepository(dao: dao),
            clientId: "client-1", botId: botId, endUserId: "12345"
        )
    }

    private func reopenWithHistory() async {
        viewModel.onCleared()
        viewModel = makeViewModel(history: makeHistory())
        await awaitUntil("room opened with history") { StubServer.requests.count >= 2 && self.viewModel.uiState.activeConversationId != nil }
        await settle()
    }

    func testTheFeedbackIconNeedsHistoryToBeConfigured() async {
        await awaitUntil("initial room") { StubServer.requests.count == 1 && self.viewModel.uiState.activeConversationId != nil }
        XCTAssertFalse(viewModel.canSendAppFeedback, "without third-party-tasks there is nowhere to store the feedback")
        await reopenWithHistory()
        XCTAssertTrue(viewModel.canSendAppFeedback)
    }

    func testTheFeedbackPopupOpensAndCloses() async {
        await awaitUntil("initial room") { StubServer.requests.count == 1 && self.viewModel.uiState.activeConversationId != nil }
        viewModel.openAppFeedback()
        XCTAssertTrue(viewModel.uiState.showAppFeedbackDialog)
        viewModel.dismissAppFeedback()
        XCTAssertFalse(viewModel.uiState.showAppFeedbackDialog)
    }

    func testSubmittingSendsTheTextWithTheRoomTheDealerAndTheEmployeeThenCloses() async throws {
        await reopenWithHistory()
        viewModel.openAppFeedback()

        viewModel.submitAppFeedback(text: "Search results are very helpful")
        await awaitUntil("feedback sent and popup closed") { !self.viewModel.uiState.showAppFeedbackDialog }

        let sent = try XCTUnwrap(StubServer.appFeedbackBodies.first)
        let body = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(sent.utf8)) as? [String: Any])
        XCTAssertEqual(body["feedback"] as? String, "Search results are very helpful")
        XCTAssertEqual(body["dealer_id"] as? String, "D1")
        XCTAssertEqual(body["emp_id"] as? String, "12345")
        XCTAssertNotNil(body["room_id"] as? String, "the room the user is in is sent")
        XCTAssertFalse(viewModel.uiState.isSendingAppFeedback)
        XCTAssertNil(viewModel.uiState.appFeedbackError)
    }

    func testAFailedSubmitKeepsThePopupOpenWithAnError() async {
        await reopenWithHistory()
        StubServer.appFeedbackStatus = 500
        viewModel.openAppFeedback()

        viewModel.submitAppFeedback(text: "Nice app")
        await awaitUntil("failure shown") { self.viewModel.uiState.appFeedbackError != nil }

        XCTAssertTrue(viewModel.uiState.showAppFeedbackDialog, "the text must not be lost")
        XCTAssertFalse(viewModel.uiState.isSendingAppFeedback, "the user can try again")
    }

    func testReopeningThePopupClearsTheOldError() async {
        await reopenWithHistory()
        StubServer.appFeedbackStatus = 500
        viewModel.openAppFeedback()
        viewModel.submitAppFeedback(text: "Nice app")
        await awaitUntil("failure shown") { self.viewModel.uiState.appFeedbackError != nil }
        viewModel.dismissAppFeedback()

        viewModel.openAppFeedback()

        XCTAssertNil(viewModel.uiState.appFeedbackError)
    }

    // MARK: - thumbs-up popup (optional remarks)

    func testTappingThumbsUpOpensThePopupAndMarksTheMessageLiked() async {
        await awaitUntil("initial room") { StubServer.requests.count == 1 && self.viewModel.uiState.activeConversationId != nil }

        viewModel.likeMessage(timestampMs: 1_700_000_000_123)

        XCTAssertEqual(viewModel.uiState.pendingLikeTimestampMs, 1_700_000_000_123, "the popup should be showing")
        XCTAssertEqual(viewModel.uiState.messageReactions[1_700_000_000_123], true)
    }

    func testSubmittingTheLikePopupClosesItAndKeepsTheLike() async {
        await awaitUntil("initial room") { StubServer.requests.count == 1 && self.viewModel.uiState.activeConversationId != nil }
        viewModel.likeMessage(timestampMs: 1_700_000_000_123)

        viewModel.submitLikeFeedback(text: "Clear and quick")

        XCTAssertNil(viewModel.uiState.pendingLikeTimestampMs)
        XCTAssertEqual(viewModel.uiState.messageReactions[1_700_000_000_123], true)
    }

    func testSubmittingTheLikePopupWithNoTextIsAllowed() async {
        await awaitUntil("initial room") { StubServer.requests.count == 1 && self.viewModel.uiState.activeConversationId != nil }
        viewModel.likeMessage(timestampMs: 1_700_000_000_123)

        viewModel.submitLikeFeedback(text: "")

        XCTAssertNil(viewModel.uiState.pendingLikeTimestampMs)
        XCTAssertEqual(viewModel.uiState.messageReactions[1_700_000_000_123], true)
    }

    func testClosingTheLikePopupStillKeepsTheLike() async {
        await awaitUntil("initial room") { StubServer.requests.count == 1 && self.viewModel.uiState.activeConversationId != nil }
        viewModel.likeMessage(timestampMs: 1_700_000_000_123)

        viewModel.skipLikeFeedback()

        XCTAssertNil(viewModel.uiState.pendingLikeTimestampMs)
        XCTAssertEqual(viewModel.uiState.messageReactions[1_700_000_000_123], true, "closing the popup must not undo the like")
    }

    func testTheLikePopupNeverBlocksTheChat() async {
        await awaitUntil("initial room") { StubServer.requests.count == 1 && self.viewModel.uiState.activeConversationId != nil }

        viewModel.likeMessage(timestampMs: 1_700_000_000_123)

        XCTAssertNil(viewModel.uiState.pendingFeedbackMessageId, "a like must not create the mandatory-feedback obligation a dislike does")
    }

    private func utcStamp(secondsAgo: TimeInterval) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: Date().addingTimeInterval(-secondsAgo))
    }

    /// An old chat with earlier user messages: opening it, and the server's session time arriving, must not show the
    /// countdown. Only the user writing in it does - and then it counts down from the server's `updated_at`.
    func testAnOldChatShowsTheTimerOnlyAfterTheUserSendsAndCountsFromTheServersUpdatedAt() async {
        await awaitUntil("initial room") { StubServer.requests.count == 1 && self.viewModel.uiState.activeConversationId != nil }
        await seedResumableRoom("conv-old", roomId: "room-old", texts: ["an earlier question"])
        await awaitUntil("old conversation listed") { self.viewModel.conversations.contains { $0.id == "conv-old" } }

        viewModel.openConversation("conv-old")
        await settle()
        XCTAssertNil(viewModel.uiState.sessionTimerExpiresAt, "opening an old chat must not show the countdown")

        await sendInOpenedRoom("room-old", text: "where is my order")
        await settle()
        XCTAssertNil(viewModel.uiState.sessionTimerExpiresAt, "sending alone shows nothing until the bot answers")

        liveReply(from: "room-old") // the answer to the send
        await settle()
        XCTAssertNil(viewModel.uiState.sessionTimerExpiresAt, "no server updated_at yet, so no countdown")

        repository.awaitingSessionTimeResponse = true // the stub socket never opens, so stand in for the request it would have sent
        // The server says this session's updated_at was 10 minutes ago: 50 minutes of the hour are left.
        repository.handleIncoming(#"{"data_type":"session_time_hyundai","found":true,"session":{"room_id":"room-old","created_at":"2020-01-01T00:00:00","updated_at":"\#(utcStamp(secondsAgo: 600))"}}"#)
        await settle()
        let remaining = viewModel.uiState.sessionTimerExpiresAt?.timeIntervalSinceNow ?? 0
        XCTAssertTrue((2_900...3_100).contains(remaining), "expected about 50 minutes left from the server's updated_at, got \(remaining)s")
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
        await sendInOpenedRoom("room-old")
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
        await sendInOpenedRoom("room-old")
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

    // MARK: - Live replies while switching between several rooms

    private var liveFrameCounter = 0

    /// A live bot frame from `room`, as the socket would hand it to the repository. Its text names the room it belongs to.
    private func liveReply(from room: String) {
        liveFrameCounter += 1
        let raw = #"{"user":"bot","room_id":"\#(room)","timestamp_int":"\#(1_700_000_000 + liveFrameCounter)","data":{"nodeType":"TEXT","nodeId":"n\#(liveFrameCounter)","questionText":"live-\#(room)-\#(liveFrameCounter)"}}"#
        repository.handleIncoming(raw)
    }

    private func seedResumableRoom(_ conversationId: String, roomId: String, texts: [String]) async {
        await seedCachedConversation(conversationId, roomId: roomId, texts: texts)
        sessionStore.save(botId: botId, session: PersistedSession(roomId: roomId, sessionToken: "tok-\(roomId)", ownerId: "owner-1"))
    }

    /// Replies from several rooms keep arriving while the user hops between them. Only one room is
    /// connected at a time, so a reply for any other room must not show up in the chat on screen.
    func testLiveRepliesFromSeveralRoomsNeverLandInTheWrongRoomWhileSwitchingRapidly() async {
        await awaitUntil("initial room") { StubServer.requests.count == 1 && self.viewModel.uiState.activeConversationId != nil }
        await seedResumableRoom("conv-a", roomId: "room-a", texts: ["a1"])
        await seedResumableRoom("conv-b", roomId: "room-b", texts: ["b1"])
        await seedResumableRoom("conv-c", roomId: "room-c", texts: ["c1"])
        await awaitUntil("conversations listed") { self.viewModel.conversations.count >= 3 }

        viewModel.openConversation("conv-a"); liveReply(from: "room-a"); liveReply(from: "room-b"); liveReply(from: "room-c")
        viewModel.openConversation("conv-b"); liveReply(from: "room-a"); liveReply(from: "room-b")
        viewModel.openConversation("conv-c"); liveReply(from: "room-c"); liveReply(from: "room-a")
        viewModel.openConversation("conv-a"); liveReply(from: "room-b"); liveReply(from: "room-a")
        viewModel.openConversation("conv-b")
        await settle()

        XCTAssertEqual(viewModel.uiState.activeConversationId, "conv-b")
        XCTAssertFalse(transcript().contains { $0.contains("live-room-a") || $0.contains("live-room-c") }, "another room's reply is in the chat: \(transcript())")

        // Once the user writes in the room they ended on, it is the connected one and receives its own replies live.
        await sendInOpenedRoom("room-b")
        await settle()
        liveReply(from: "room-b")
        await settle()
        XCTAssertEqual(transcript().last, "live-room-b-\(liveFrameCounter)", "the connected room's reply was lost: \(transcript())")

        // Moving on shows that room alone - nothing carried over from b.
        viewModel.openConversation("conv-c")
        await settle()
        XCTAssertFalse(transcript().contains { $0.contains("live-room-a") || $0.contains("live-room-b") }, "another room's reply is in the chat: \(transcript())")
        liveReply(from: "room-a") // a reply for the room just left
        await settle()
        XCTAssertFalse(transcript().contains { $0.contains("live-room-a") }, "a late reply from a previous room landed here: \(transcript())")
    }

    /// The user sends a message and taps New chat before the bot has answered. The repository keeps the old
    /// room's socket open (up to 10s) for that reply, so it can still arrive after the new chat is on screen
    /// - and it must not show up there, nor be saved under the new conversation.
    func testAReplyStillInFlightFromTheRoomJustLeftNeverLandsInTheNewChat() async {
        await awaitUntil("initial room") { StubServer.requests.count == 1 && self.viewModel.uiState.activeConversationId != nil }
        let oldConversation = viewModel.uiState.activeConversationId
        // The room already has a conversation (the stub's history), so it is not a blank room New chat would reuse.
        await awaitUntil("the room's history") { self.transcript().contains("Tell me about Hyundai Venue features") }
        viewModel.onInputChange("And what about the price?")
        viewModel.sendMessage() // the bot's reply to this is now outstanding on room-1
        await settle()

        viewModel.startNewChat()
        await awaitUntil("the new chat is on screen") {
            self.viewModel.uiState.activeConversationId != oldConversation && self.transcript().isEmpty
        }
        let newConversation = viewModel.uiState.activeConversationId!
        // The new room's own activation clears the screen shortly after, so watch every state change
        // instead of only looking at the end - a reply that flashes into the new chat is still a leak.
        var everShownInNewChat = false
        let watcher = viewModel.$uiState.sink { state in
            if state.activeConversationId == newConversation, state.messages.contains(where: { $0.text.contains("live-room-1") }) {
                everShownInNewChat = true
            }
        }
        defer { watcher.cancel() }

        liveReply(from: "room-1") // the reply to the question, from the room that was just left
        await settle()

        XCTAssertFalse(everShownInNewChat, "the old room's reply appeared in the new chat")
        XCTAssertFalse(transcript().contains { $0.contains("live-room-1") }, "the old room's reply is in the new chat: \(transcript())")
        let savedInNewChat = await dao.messages(conversationId: newConversation).map { $0.payload }
        XCTAssertFalse(savedInNewChat.contains { $0.contains("live-room-1") }, "the old room's reply was saved under the new chat: \(savedInNewChat)")
        let savedInOldChat = await dao.messages(conversationId: oldConversation!).map { $0.payload }
        XCTAssertTrue(savedInOldChat.contains { $0.contains("live-room-1") }, "the reply was not kept with the room it belongs to: \(savedInOldChat)")
    }

    /// Same as above, but the user leaves by opening a saved conversation from the drawer instead of tapping New chat.
    func testAReplyStillInFlightFromTheRoomJustLeftStaysOutOfTheConversationOpenedNext() async {
        await awaitUntil("initial room") { StubServer.requests.count == 1 && self.viewModel.uiState.activeConversationId != nil }
        let oldConversation = viewModel.uiState.activeConversationId!
        await seedResumableRoom("conv-a", roomId: "room-a", texts: ["a1"])
        await awaitUntil("conversation listed") { self.viewModel.conversations.contains { $0.id == "conv-a" } }
        await awaitUntil("the room's history") { self.transcript().contains("Tell me about Hyundai Venue features") }
        viewModel.onInputChange("And what about the price?")
        viewModel.sendMessage() // the bot's reply to this is now outstanding on room-1
        await settle()

        var everShownInOpenedChat = false
        let watcher = viewModel.$uiState.sink { state in
            if state.activeConversationId == "conv-a", state.messages.contains(where: { $0.text.contains("live-room-1") }) {
                everShownInOpenedChat = true
            }
        }
        defer { watcher.cancel() }

        viewModel.openConversation("conv-a")
        liveReply(from: "room-1") // the reply to the question, from the room that was just left
        await settle()

        XCTAssertFalse(everShownInOpenedChat, "the old room's reply appeared in the conversation that was opened")
        XCTAssertFalse(transcript().contains { $0.contains("live-room-1") }, "the old room's reply is in the opened conversation: \(transcript())")
        let savedInOpenedChat = await dao.messages(conversationId: "conv-a").map { $0.payload }
        XCTAssertFalse(savedInOpenedChat.contains { $0.contains("live-room-1") }, "the old room's reply was saved under the opened conversation: \(savedInOpenedChat)")
        let savedInOldChat = await dao.messages(conversationId: oldConversation).map { $0.payload }
        XCTAssertTrue(savedInOldChat.contains { $0.contains("live-room-1") }, "the reply was not kept with the room it belongs to: \(savedInOldChat)")
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
