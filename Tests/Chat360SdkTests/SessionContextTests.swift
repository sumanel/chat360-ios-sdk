import XCTest
@testable import Chat360SDK

/// The session timer and the host's variables (emp id, dealer id, ...) - feedback from the Hyundai integration:
/// - the timer started by itself when a new chat opened, before the user typed anything;
/// - a room joined without session-init, or a session the backend renewed after an hour, had no emp id,
///   so the bot answered "we could not fetch response".
final class SessionContextTests: XCTestCase {

    /// Answers session-init and 404s everything else, without touching the network.
    private final class StubSessions: URLProtocol {
        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func stopLoading() {}
        override func startLoading() {
            let url = request.url!
            let isSession = url.path.contains("/session/")
            let body = isSession ? Data(#"{"room_id":"room-1","owner_id":"owner-1","session_token":"tok","nodeType":"INIT","targetId":"t1"}"#.utf8) : Data()
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: isSession ? 200 : 404, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    /// Knows the last room's owner, but has never connected to "room-elsewhere" from this device.
    private final class OwnerOnlyStore: SessionStore {
        func load(botId: String) -> PersistedSession? { PersistedSession(roomId: "room-last", sessionToken: "tok", ownerId: "owner-1") }
        func loadForRoom(botId: String, roomId: String) -> PersistedSession? { nil }
        func save(botId: String, session: PersistedSession) {}
    }

    private var repositories: [ChatRepository] = []

    override func tearDown() {
        repositories.forEach { $0.disconnect() }
        repositories = []
        super.tearDown()
    }

    private func makeRepository(meta: [String: String]? = nil, dealerId: String? = nil, empId: String? = nil, sessionStore: SessionStore? = nil) -> ChatRepository {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubSessions.self]
        let baseUrl = "http://127.0.0.1:1"
        let repository = ChatRepository(
            baseUrl: baseUrl,
            botId: "session-context-bot-\(UUID().uuidString)",
            apiService: Chat360ApiService(baseUrl: baseUrl, session: URLSession(configuration: configuration)),
            sessionStore: sessionStore,
            meta: meta,
            dealerId: dealerId,
            empId: empId
        )
        repositories.append(repository)
        return repository
    }

    private func message(_ text: String, variables: [String: String]? = nil) -> OutgoingMessage {
        OutgoingMessage(message: .string(text), bot_id: "bot", targetId: nil, variables: variables)
    }

    private var frameCounter = 0

    /// A live bot reply from `room`, delivered the way the socket would.
    private func botReply(_ repository: ChatRepository, room: String = "room-1") {
        frameCounter += 1
        repository.handleIncoming(#"{"user":"bot","room_id":"\#(room)","timestamp_int":"\#(1_700_000_000 + frameCounter)","data":{"nodeType":"TEXT","nodeId":"n\#(frameCounter)","questionText":"reply \#(frameCounter)"}}"#)
    }

    /// The server's answer to a session-time request.
    private func sessionTimeAnswer(_ repository: ChatRepository, room: String = "room-1") {
        repository.handleIncoming(#"{"data_type":"session_time_hyundai","found":true,"session":{"room_id":"\#(room)","created_at":"2020-01-01T00:00:00.000000","updated_at":"2026-09-01T10:00:00.000000"}}"#)
    }

    private func connected(_ repository: ChatRepository, onSessionTime: @escaping (Date) -> Void = { _ in }) async {
        await repository.connect(onEvent: { _ in }, onConnected: {}, onError: { _ in }, onConversationStarted: { _ in false }, onSessionTimeReceived: onSessionTime)
    }

    // MARK: - the timer must not start by itself

    func testTheBotsOpeningMessageDoesNotStartTheTimer() async {
        let repository = makeRepository()
        var times: [Date] = []
        await connected(repository) { times.append($0) }

        botReply(repository)          // the welcome message - the user has typed nothing
        sessionTimeAnswer(repository) // whatever the backend pushes next is not the answer to a request of ours

        XCTAssertTrue(times.isEmpty, "the countdown was started by the welcome message: \(times)")
    }

    func testTheTimerStartsFromTheBotsReplyToTheUsersFirstMessage() async {
        let repository = makeRepository()
        var times: [Date] = []
        await connected(repository) { times.append($0) }
        botReply(repository) // welcome message

        repository.sendFreeText("Tell me about the Venue")
        botReply(repository)          // the reply asks the server for the session time...
        sessionTimeAnswer(repository) // ...and this is its answer

        XCTAssertEqual(times.count, 1)
    }

    // MARK: - coming back after the hour

    func testSendingAfterTheHourHasRunOutRestartsTheCountdownFromTheBotsReply() async {
        let repository = makeRepository()
        var times: [Date] = []
        await connected(repository) { times.append($0) }
        repository.lastSessionCreatedAt = Date().addingTimeInterval(-3_700)

        repository.sendFreeText("Another question")
        XCTAssertTrue(times.isEmpty, "the timer must not restart before the bot has replied")
        botReply(repository)

        XCTAssertEqual(times.count, 1)
        XCTAssertLessThan(abs(times[0].timeIntervalSinceNow), 5, "restarted at 'now', not at the old start")
    }

    func testSendingWithinTheHourLeavesTheRunningCountdownAlone() async {
        let repository = makeRepository()
        var times: [Date] = []
        await connected(repository) { times.append($0) }
        repository.lastSessionCreatedAt = Date().addingTimeInterval(-60)

        repository.sendFreeText("Another question")
        botReply(repository)

        XCTAssertTrue(times.isEmpty)
    }

    // MARK: - the countdown anchors to updated_at

    func testAReplyWithOnlyCreatedAtStartsNoTimer() async {
        let repository = makeRepository()
        var times: [Date] = []
        await connected(repository) { times.append($0) }
        botReply(repository)
        repository.sendFreeText("question")
        botReply(repository) // asks the server for the session time

        repository.handleIncoming(#"{"data_type":"session_time_hyundai","found":true,"session":{"room_id":"room-1","created_at":"2026-09-01T10:00:00.000000"}}"#)

        XCTAssertTrue(times.isEmpty, "created_at must not start the timer: \(times)")
    }

    func testTheTimerAnchorsToUpdatedAtNotCreatedAt() async {
        let repository = makeRepository()
        var times: [Date] = []
        await connected(repository) { times.append($0) }
        repository.awaitingSessionTimeResponse = true

        repository.handleIncoming(#"{"data_type":"session_time_hyundai","found":true,"session":{"room_id":"room-1","created_at":"2020-01-01T00:00:00.000000","updated_at":"2026-09-01T10:00:00.000000"}}"#)

        let anchor = ISO8601DateFormatter().date(from: "2026-09-01T10:00:00Z")
        XCTAssertEqual(times.first, anchor)
    }

    // MARK: - the host's variables

    func testTheMessageAfterAnHourOfSilenceCarriesTheHostsVariablesAgain() async {
        let repository = makeRepository(meta: ["region": "south"], dealerId: "W4300", empId: "EMP1101")
        repository.lastSessionCreatedAt = Date().addingTimeInterval(-3_700)

        let outgoing = repository.prepareOutgoing(message("Another question"))

        XCTAssertEqual(outgoing.variables, ["region": "south", "dealer_id": "W4300", "emp_id": "EMP1101"])
    }

    func testTheHostsVariablesGoOutOnceNotWithEveryMessage() async {
        let repository = makeRepository(empId: "EMP1101")
        repository.lastSessionCreatedAt = Date().addingTimeInterval(-3_700)

        let first = repository.prepareOutgoing(message("first"))
        let second = repository.prepareOutgoing(message("second"))

        XCTAssertEqual(first.variables, ["emp_id": "EMP1101"])
        XCTAssertNil(second.variables, "sent again with the next message")
    }

    func testAnOrdinaryMessageCarriesNoExtraVariables() async {
        let repository = makeRepository(meta: ["region": "south"], empId: "EMP1101")

        XCTAssertNil(repository.prepareOutgoing(message("hello")).variables)
    }

    func testTheAnswerBeingSubmittedWinsOverAHostKeyOfTheSameName() async {
        let repository = makeRepository(empId: "EMP1101")
        repository.lastSessionCreatedAt = Date().addingTimeInterval(-3_700)

        let outgoing = repository.prepareOutgoing(message("EMP9999", variables: ["emp_id": "EMP9999"]))

        XCTAssertEqual(outgoing.variables, ["emp_id": "EMP9999"])
    }

    func testARoomJoinedWithoutSessionInitStillGetsTheHostsVariablesWithTheFirstMessage() async {
        let repository = makeRepository(meta: ["region": "south"], empId: "EMP1101", sessionStore: OwnerOnlyStore())

        let joined = await repository.switchToRoom(targetRoomId: "room-elsewhere", onConversationStarted: { _ in true })
        XCTAssertTrue(joined)
        let outgoing = repository.prepareOutgoing(message("hello from the old room"))

        XCTAssertEqual(outgoing.variables, ["region": "south", "emp_id": "EMP1101"])
    }
}
