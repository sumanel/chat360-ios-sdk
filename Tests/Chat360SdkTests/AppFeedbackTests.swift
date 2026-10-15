import SQLite3
import XCTest
@testable import Chat360SDK

/// The application-wide feedback: the drawer's feedback icon opens a popup, and its text goes to
/// `POST /api/third-party-tasks/app-feedback` together with the room, dealer and employee.
@available(iOS 16.0, *)
final class AppFeedbackTests: XCTestCase {

    private final class FeedbackStub: URLProtocol {
        static let lock = NSLock()
        static var statuses: [Int] = []
        static var requests: [(request: URLRequest, body: Data)] = []

        static func reset(statuses: [Int] = [200]) { lock.lock(); self.statuses = statuses; requests = []; lock.unlock() }
        static var seen: [(request: URLRequest, body: Data)] { lock.lock(); defer { lock.unlock() }; return requests }

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func stopLoading() {}
        override func startLoading() {
            var body = Data()
            if let stream = request.httpBodyStream {
                stream.open()
                var buffer = [UInt8](repeating: 0, count: 4096)
                while stream.hasBytesAvailable {
                    let read = stream.read(&buffer, maxLength: buffer.count)
                    if read <= 0 { break }
                    body.append(buffer, count: read)
                }
                stream.close()
            } else if let data = request.httpBody {
                body = data
            }
            Self.lock.lock()
            Self.requests.append((request, body))
            let status = Self.statuses.isEmpty ? 200 : Self.statuses.removeFirst()
            Self.lock.unlock()
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data("{}".utf8))
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    private func api() -> ThirdPartyTasksApiService {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FeedbackStub.self]
        return ThirdPartyTasksApiService(baseUrl: "https://staging.test", session: URLSession(configuration: configuration))
    }

    private func repository() -> ChatHistoryRepository {
        var handle: OpaquePointer?
        sqlite3_open(":memory:", &handle)
        return ChatHistoryRepository(
            apiService: api(),
            tokenManager: ThirdPartyTokenManager(fetchToken: { TokenResponse(bearerToken: "tok-1") }),
            cache: ChatCacheRepository(dao: ChatCacheDao(db: handle!)),
            clientId: "client-1", botId: "bot-1", endUserId: "EMP101"
        )
    }

    private func json(_ data: Data) throws -> [String: Any] {
        try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    override func setUp() { FeedbackStub.reset() }

    // MARK: - the request

    func testItPostsToTheAppFeedbackEndpointWithTheBearerToken() async throws {
        try await api().submitAppFeedback(roomId: "room-1", feedback: "Search results are very helpful", dealerId: "D1", empId: "EMP101", bearerToken: "tok-1")

        let sent = try XCTUnwrap(FeedbackStub.seen.first)
        XCTAssertEqual(sent.request.httpMethod, "POST")
        XCTAssertEqual(sent.request.url?.path, "/api/third-party-tasks/app-feedback")
        XCTAssertEqual(sent.request.value(forHTTPHeaderField: "Authorization"), "Bearer tok-1")
        XCTAssertEqual(sent.request.value(forHTTPHeaderField: "Content-Type"), "application/json")
    }

    func testTheBodyCarriesTheRoomTheFeedbackTheDealerAndTheEmployee() async throws {
        try await api().submitAppFeedback(roomId: "room-1", feedback: "Search results are very helpful", dealerId: "D1", empId: "EMP101", bearerToken: "tok-1")

        let body = try json(try XCTUnwrap(FeedbackStub.seen.first).body)
        XCTAssertEqual(body["room_id"] as? String, "room-1")
        XCTAssertEqual(body["feedback"] as? String, "Search results are very helpful")
        XCTAssertEqual(body["dealer_id"] as? String, "D1")
        XCTAssertEqual(body["emp_id"] as? String, "EMP101")
        XCTAssertEqual(Set(body.keys), ["room_id", "feedback", "dealer_id", "emp_id"], "no other fields are sent")
    }

    func testADealerOrEmployeeTheHostNeverSetIsLeftOut() async throws {
        try await api().submitAppFeedback(roomId: "room-1", feedback: "Nice", dealerId: nil, empId: "EMP101", bearerToken: "tok-1")

        let body = try json(try XCTUnwrap(FeedbackStub.seen.first).body)
        XCTAssertNil(body["dealer_id"])
        XCTAssertEqual(body["emp_id"] as? String, "EMP101")
    }

    func testAServerErrorThrows() async {
        FeedbackStub.reset(statuses: [500])
        do {
            try await api().submitAppFeedback(roomId: "room-1", feedback: "Nice", dealerId: "D1", empId: "EMP101", bearerToken: "tok-1")
            XCTFail("a 500 must not look like success")
        } catch {}
    }

    // MARK: - the repository (token + result)

    func testTheRepositorySendsWithItsOwnTokenAndReportsSuccess() async throws {
        let ok = await repository().submitAppFeedback(roomId: "room-1", feedback: "  Very helpful \n", dealerId: "D1", empId: "EMP101")

        XCTAssertTrue(ok)
        let sent = try XCTUnwrap(FeedbackStub.seen.first)
        XCTAssertEqual(sent.request.value(forHTTPHeaderField: "Authorization"), "Bearer tok-1")
        XCTAssertEqual(try json(sent.body)["feedback"] as? String, "Very helpful", "the text is trimmed")
    }

    func testTheRepositoryReportsAFailure() async {
        FeedbackStub.reset(statuses: [500])
        let ok = await repository().submitAppFeedback(roomId: "room-1", feedback: "Nice", dealerId: "D1", empId: "EMP101")
        XCTAssertFalse(ok)
    }

    func testTheRepositoryRetriesOnceWithAFreshTokenAfter401() async throws {
        FeedbackStub.reset(statuses: [401, 200])
        let ok = await repository().submitAppFeedback(roomId: "room-1", feedback: "Nice", dealerId: "D1", empId: "EMP101")
        XCTAssertTrue(ok)
        XCTAssertEqual(FeedbackStub.seen.count, 2)
    }

    func testBlankFeedbackIsNeverSent() async {
        let ok = await repository().submitAppFeedback(roomId: "room-1", feedback: "  \n ", dealerId: "D1", empId: "EMP101")
        XCTAssertFalse(ok)
        XCTAssertTrue(FeedbackStub.seen.isEmpty)
    }

    // MARK: - who the feedback is from

    func testTheHostsDealerAndEmployeeWin() {
        let identity = AppFeedbackIdentity.resolve(dealerId: "D9", empId: "EMP9", meta: ["dealer_id": "D1", "emp_id": "EMP1"], endUserId: "EMP5")
        XCTAssertEqual(identity.dealerId, "D9")
        XCTAssertEqual(identity.empId, "EMP9")
    }

    func testTheMetaIsUsedWhenTheHostSetNoDealerOrEmployee() {
        let identity = AppFeedbackIdentity.resolve(dealerId: nil, empId: nil, meta: ["dealer_id": "D1", "emp_id": "12345"], endUserId: "EMP5")
        XCTAssertEqual(identity.dealerId, "D1")
        XCTAssertEqual(identity.empId, "12345")
    }

    func testTheEndUserIdIsTheEmployeeOfLastResort() {
        let identity = AppFeedbackIdentity.resolve(dealerId: nil, empId: nil, meta: nil, endUserId: "EMP5")
        XCTAssertNil(identity.dealerId)
        XCTAssertEqual(identity.empId, "EMP5")
    }

    func testBlankValuesCountAsNotSet() {
        let identity = AppFeedbackIdentity.resolve(dealerId: " ", empId: "", meta: ["dealer_id": "D1"], endUserId: " EMP5 ")
        XCTAssertEqual(identity.dealerId, "D1")
        XCTAssertEqual(identity.empId, "EMP5")
    }

    // MARK: - the popup

    func testTheAppFeedbackPopupNeedsSomeText() {
        XCTAssertEqual(FeedbackDialogKind.appFeedback.minCharCount, 1)
    }

    func testTheMenuIconIsOffUntilTheHostTurnsItOn() {
        XCTAssertFalse(Chat360FeatureConfig().showAppFeedback)
        XCTAssertTrue(Chat360FeatureConfig(showAppFeedback: true).showAppFeedback)
    }
}
