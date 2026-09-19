import XCTest
@testable import Chat360SDK

/// The sales-executive gate closes the chat ONLY on a successful reply that says INACTIVE. Every other outcome -
/// a failing, missing, slow or nonsensical check - must let the user through with the bot flow untouched.
/// The replies below are the real ones from staging.
final class SalesExecutiveGateTests: XCTestCase {

    private final class GateStub: URLProtocol {
        struct Reply { var status = 200; var body = ""; var delay: TimeInterval = 0; var failure: URLError.Code? }
        static let lock = NSLock()
        static var replies: [Reply] = []
        static var requests: [(request: URLRequest, body: Data)] = []

        static func reset() { lock.lock(); replies = []; requests = []; lock.unlock() }
        static func enqueue(_ reply: Reply) { lock.lock(); replies.append(reply); lock.unlock() }
        static func enqueue(_ body: String, status: Int = 200) { enqueue(Reply(status: status, body: body)) }
        static var seen: [(request: URLRequest, body: Data)] { lock.lock(); defer { lock.unlock() }; return requests }

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func stopLoading() {}
        override func startLoading() {
            var body = request.httpBody ?? Data()
            if body.isEmpty, let stream = request.httpBodyStream {
                stream.open(); defer { stream.close() }
                var buffer = [UInt8](repeating: 0, count: 4096)
                while stream.hasBytesAvailable { let n = stream.read(&buffer, maxLength: buffer.count); if n <= 0 { break }; body.append(buffer, count: n) }
            }
            Self.lock.lock()
            Self.requests.append((request, body))
            let reply = Self.replies.isEmpty ? Reply(status: 404) : Self.replies.removeFirst()
            Self.lock.unlock()
            DispatchQueue.global().asyncAfter(deadline: .now() + reply.delay) { [self] in
                if let failure = reply.failure {
                    client?.urlProtocol(self, didFailWithError: URLError(failure))
                    return
                }
                client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: reply.status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: Data(reply.body.utf8))
                client?.urlProtocolDidFinishLoading(self)
            }
        }
    }

    private let details = ["dealer_code": "W4300", "emp_code": "EMP1101"]

    /// Onboarded as INACTIVE - the reply the server gave for a brand-new executive.
    private let inactiveReply = #"{"success":true,"message":"Sales Executive onboarded as INACTIVE.","is_new":true,"status_downgraded_to_inactive":false,"sales_executive":{"id":12,"emp_code":"EMP1101","name":"","role":null,"dealer_code":"W4300","dealer_name":"Hindustan Hyundai","status":"INACTIVE"}}"#

    /// A known, active executive - what staging answers for EMP1101 today.
    private let activeReply = #"{"success":true,"message":"Sales Executive validated successfully.","is_new":false,"status_downgraded_to_inactive":false,"sales_executive":{"id":12,"emp_code":"EMP1101","name":"","role":"Trainer","dealer_code":"W4300","dealer_name":"Hindustan Hyundai","status":"ACTIVE"}}"#

    private var api: ThirdPartyTasksApiService!

    override func setUp() {
        GateStub.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [GateStub.self]
        api = ThirdPartyTasksApiService(baseUrl: "https://staging.test", session: URLSession(configuration: configuration))
    }

    private func gate(_ map: [String: String]? = nil, timeout: TimeInterval = 3) -> SalesExecutiveGate {
        SalesExecutiveGate(apiService: api, clientId: "client-1", details: map ?? details, timeout: timeout)
    }

    // MARK: - the request

    func testItPostsTheDetailsAsJSONWithAClientIdHeaderAndNoBearerToken() async throws {
        GateStub.enqueue(activeReply)

        _ = await gate(details.merging(["name": "Ravi Kumar", "status": "INACTIVE"]) { $1 }).blockedMessage()

        let sent = try XCTUnwrap(GateStub.seen.first)
        XCTAssertEqual(sent.request.httpMethod, "POST")
        XCTAssertEqual(sent.request.url?.path, "/api/third-party-tasks/sales-exectives")
        XCTAssertEqual(sent.request.value(forHTTPHeaderField: "Client-Id"), "client-1")
        XCTAssertNil(sent.request.value(forHTTPHeaderField: "client_id"), "the server rejects the underscored spelling")
        XCTAssertNil(sent.request.value(forHTTPHeaderField: "Authorization"))
        // Without this content type the live server ignores the body and reports both fields as required.
        XCTAssertEqual(sent.request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: sent.body) as? [String: String])
        XCTAssertEqual(body, ["dealer_code": "W4300", "emp_code": "EMP1101", "name": "Ravi Kumar", "status": "INACTIVE"])
    }

    func testOptionalFieldsAreOptionalOnlyDealerCodeAndEmpCodeAreNeeded() async throws {
        GateStub.enqueue(activeReply)

        _ = await gate().blockedMessage()

        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(GateStub.seen.first).body) as? [String: String])
        XCTAssertEqual(Set(body.keys), ["dealer_code", "emp_code"])
    }

    func testWithoutADealerCodeAndEmpCodeItNeverAsks() async {
        let missingDealer = await gate(["emp_code": "EMP1101"]).blockedMessage()
        let blankEmp = await gate(["dealer_code": "W4300", "emp_code": "  "]).blockedMessage()
        let empty = await gate([:]).blockedMessage()

        XCTAssertNil(missingDealer); XCTAssertNil(blankEmp); XCTAssertNil(empty)
        XCTAssertEqual(GateStub.seen.count, 0)
    }

    // MARK: - when it closes the chat

    func testAnInactiveExecutiveClosesTheChatWithTheServersMessage() async {
        GateStub.enqueue(inactiveReply)
        let message = await gate().blockedMessage()
        XCTAssertEqual(message, "Sales Executive onboarded as INACTIVE.")
    }

    func testTheStatusIsComparedWithoutRegardToCase() async {
        GateStub.enqueue(inactiveReply.replacingOccurrences(of: "\"INACTIVE\"}", with: "\"inactive\"}"))
        let message = await gate().blockedMessage()
        XCTAssertNotNil(message)
    }

    func testABlankServerMessageFallsBackToADefaultSoTheScreenIsNeverEmpty() async {
        GateStub.enqueue(inactiveReply.replacingOccurrences(of: "Sales Executive onboarded as INACTIVE.", with: ""))
        let message = await gate().blockedMessage()
        XCTAssertEqual(message, SalesExecutiveGate.defaultMessage)
    }

    // MARK: - everything else lets the user through

    func testAnActiveExecutiveIsLetThrough() async {
        GateStub.enqueue(activeReply)
        let message = await gate().blockedMessage()
        XCTAssertNil(message)
    }

    func testInactiveOnAnUnsuccessfulReplyIsNotTrusted() async {
        GateStub.enqueue(inactiveReply.replacingOccurrences(of: "\"success\":true", with: "\"success\":false"))
        let message = await gate().blockedMessage()
        XCTAssertNil(message)
    }

    func testAnUnknownOrMissingStatusIsLetThrough() async {
        GateStub.enqueue(activeReply.replacingOccurrences(of: "\"ACTIVE\"", with: "\"SUSPENDED\""))
        GateStub.enqueue(#"{"success":true,"message":"ok","sales_executive":{}}"#)
        GateStub.enqueue(#"{"success":true,"message":"ok"}"#)

        for _ in 0..<3 {
            let message = await gate().blockedMessage()
            XCTAssertNil(message)
        }
    }

    func testEveryKindOfFailureLetsTheUserThrough() async {
        let failures: [GateStub.Reply] = [
            // what the live server answers for validation errors, an unconfigured client and the wrong header spelling
            .init(status: 400, body: #"{"success":false,"errors":{"emp_code":["This field is required."]}}"#),
            .init(status: 400, body: #"{"success":false,"message":"Sales executive onboarding is not configured for this client."}"#),
            .init(status: 400, body: #"{"detail":"client_id header is required"}"#),
            .init(status: 404, body: "<!DOCTYPE html><html>Page not found</html>"), // endpoint not deployed
            .init(status: 401), .init(status: 500),
            .init(status: 200, body: "<html>a proxy error page</html>"),
            .init(status: 200, body: #"["not","an","object"]"#),
            .init(status: 200, body: "{ this is not json"),
            .init(status: 200, body: ""),
            .init(failure: .notConnectedToInternet), .init(failure: .cannotConnectToHost), .init(failure: .timedOut),
        ]
        for reply in failures {
            GateStub.enqueue(reply)
            let message = await gate().blockedMessage()
            XCTAssertNil(message, "blocked on: status \(reply.status) \(reply.body.prefix(30)) \(String(describing: reply.failure))")
        }
    }

    func testASlowServerLetsTheUserThroughOnceTheTimeoutPassesInsteadOfStallingTheChat() async {
        GateStub.enqueue(.init(status: 200, body: inactiveReply, delay: 3))
        let started = Date()

        let message = await gate(timeout: 0.3).blockedMessage()

        XCTAssertNil(message, "a reply that arrives after the timeout must not block")
        XCTAssertLessThan(Date().timeIntervalSince(started), 2, "waited for the slow request instead of giving up at the timeout")
    }

    // MARK: - remembering the answer

    func testOnceTheServerSaysTheExecutiveIsActiveItIsNotAskedAgainThisSession() async {
        GateStub.enqueue(activeReply)
        let gate = gate()

        for _ in 0..<3 { let message = await gate.blockedMessage(); XCTAssertNil(message) }

        XCTAssertEqual(GateStub.seen.count, 1, "re-asking on every foreground would only add traffic")
    }

    func testABlockIsRecheckedEveryTimeSoAnExecutiveWhoIsActivatedGetsIn() async {
        GateStub.enqueue(inactiveReply)
        GateStub.enqueue(activeReply)
        let gate = gate()

        let first = await gate.blockedMessage()
        let second = await gate.blockedMessage()

        XCTAssertNotNil(first)
        XCTAssertNil(second, "an admin activated the executive")
        XCTAssertEqual(GateStub.seen.count, 2)
    }

    func testAFailureIsNotRememberedAsABlockAndNotAsAPassEither() async {
        GateStub.enqueue("", status: 500)
        GateStub.enqueue(inactiveReply)
        let gate = gate()

        let first = await gate.blockedMessage()
        let second = await gate.blockedMessage()

        XCTAssertNil(first)
        XCTAssertNotNil(second, "the next check must really ask again")
    }

    func testOverlappingChecksShareOneRequest() async {
        GateStub.enqueue(.init(status: 200, body: inactiveReply, delay: 0.3))
        let gate = gate()

        async let startup = gate.blockedMessage()
        async let foreground = gate.blockedMessage()
        let results = await [startup, foreground]

        XCTAssertEqual(GateStub.seen.count, 1, "start-up and a foreground resume each sent their own request")
        XCTAssertEqual(results, ["Sales Executive onboarded as INACTIVE.", "Sales Executive onboarded as INACTIVE."])
    }
}
