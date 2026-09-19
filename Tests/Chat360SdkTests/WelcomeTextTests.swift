import XCTest
@testable import Chat360SDK

/// The server-configured welcome copy: the request, how the reply is read, and how it combines with what the host app set.
final class WelcomeTextTests: XCTestCase {

    private final class WelcomeStub: URLProtocol {
        static let lock = NSLock()
        static var replies: [(status: Int, body: String)] = []
        static var requests: [URLRequest] = []

        static func reset() { lock.lock(); replies = []; requests = []; lock.unlock() }
        static func enqueue(_ body: String, status: Int = 200) { lock.lock(); replies.append((status, body)); lock.unlock() }
        static var seen: [URLRequest] { lock.lock(); defer { lock.unlock() }; return requests }

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func stopLoading() {}
        override func startLoading() {
            Self.lock.lock()
            Self.requests.append(request)
            let reply = Self.replies.isEmpty ? (status: 404, body: "") : Self.replies.removeFirst()
            Self.lock.unlock()
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: reply.status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(reply.body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    private final class MemoryStore: WelcomeTextStore {
        var saved: WelcomeText?
        init(_ saved: WelcomeText? = nil) { self.saved = saved }
        func load(clientId: String) -> WelcomeText? { saved }
        func save(clientId: String, welcomeText: WelcomeText?) { saved = welcomeText }
    }

    private var api: ThirdPartyTasksApiService!

    override func setUp() {
        WelcomeStub.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [WelcomeStub.self]
        api = ThirdPartyTasksApiService(baseUrl: "https://staging.test", session: URLSession(configuration: configuration))
    }

    // MARK: - the request and the reply

    func testItAsksForTheClientsWelcomeTextWithAClientIdHeaderAndNoBearerToken() async throws {
        WelcomeStub.enqueue(#"{"heading":"Hi","text":"Ask me anything","client_id":"client-1"}"#)

        _ = try await api.fetchWelcomeText(clientId: "client-1")

        let request = try XCTUnwrap(WelcomeStub.seen.first)
        XCTAssertEqual(request.httpMethod ?? "GET", "GET")
        XCTAssertEqual(request.url?.path, "/api/third-party-tasks/welcome-text")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Client-Id"), "client-1")
        // The live server rejects the underscored spelling ("client_id header is required"), so it must never be sent.
        XCTAssertNil(request.value(forHTTPHeaderField: "client_id"))
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"), "no bearer token is needed for this endpoint")
    }

    func testABareReplyWithHeadingAndTextIsRead() async throws {
        WelcomeStub.enqueue(#"{"heading":"Welcome to Hyundai","text":"I can help you choose a car.","client_id":"client-1"}"#)
        let result = try await api.fetchWelcomeText(clientId: "client-1")
        XCTAssertEqual(result, WelcomeText(heading: "Welcome to Hyundai", text: "I can help you choose a car."))
    }

    func testAReplyWrappedInDataLikeTheOtherThirdPartyEndpointsIsReadToo() async throws {
        WelcomeStub.enqueue(#"{"success":true,"data":{"heading":"Welcome","text":"Hello there","client_id":"client-1"}}"#)
        let result = try await api.fetchWelcomeText(clientId: "client-1")
        XCTAssertEqual(result, WelcomeText(heading: "Welcome", text: "Hello there"))
    }

    func testDataAsAListOfObjectsIsReadWhetherItHoldsOneEntryOrSeveral() async throws {
        WelcomeStub.enqueue(#"{"success":true,"data":[{"heading":"List heading","text":"List text"}]}"#)
        WelcomeStub.enqueue(#"{"success":true,"data":[{"heading":"First","text":"One"},{"heading":"Second","text":"Two"}]}"#)

        let single = try await api.fetchWelcomeText(clientId: "client-1")
        let several = try await api.fetchWelcomeText(clientId: "client-1")

        XCTAssertEqual(single, WelcomeText(heading: "List heading", text: "List text"))
        XCTAssertEqual(several, WelcomeText(heading: "First", text: "One"), "the first entry wins")
    }

    func testInAListAnEmptyEntryIsSkippedInFavourOfTheFirstOneThatHasContent() async throws {
        WelcomeStub.enqueue(#"{"data":[{"heading":"","text":""},"not an object",{"heading":"Real heading","text":"Real text"}]}"#)
        let result = try await api.fetchWelcomeText(clientId: "client-1")
        XCTAssertEqual(result, WelcomeText(heading: "Real heading", text: "Real text"))
    }

    func testAListWhoseEntriesAreAllEmptyMeansNothingIsConfigured() async throws {
        WelcomeStub.enqueue(#"{"success":true,"data":[{"heading":"","text":""},{}]}"#)
        let result = try await api.fetchWelcomeText(clientId: "client-1")
        XCTAssertNil(result)
    }

    func testAFieldThatIsBlankCountsAsNotConfiguredTheOtherOneIsStillUsed() async throws {
        WelcomeStub.enqueue(#"{"heading":"   ","text":"Only the subtitle"}"#)
        let result = try await api.fetchWelcomeText(clientId: "client-1")
        XCTAssertEqual(result, WelcomeText(heading: nil, text: "Only the subtitle"))
    }

    func testTheServersEmptyReplyDataAsAnEmptyArrayMeansNothingIsConfigured() async throws {
        // Exactly what staging returns for a client with no welcome text set.
        WelcomeStub.enqueue(#"{"success":true,"data":[]}"#)
        let result = try await api.fetchWelcomeText(clientId: "client-1")
        XCTAssertNil(result)
    }

    func testBothFieldsEmptyOrNullMeansNothingIsConfigured() async throws {
        WelcomeStub.enqueue(#"{"heading":"","text":null,"client_id":"client-1"}"#)
        WelcomeStub.enqueue(#"{"success":true,"data":{}}"#)
        let first = try await api.fetchWelcomeText(clientId: "client-1")
        let second = try await api.fetchWelcomeText(clientId: "client-1")
        XCTAssertNil(first)
        XCTAssertNil(second)
    }

    func testTheEndpointNotBeingDeployedYetOrAnyErrorThrowsInsteadOfPretendingThereIsNoText() async {
        let replies: [(Int, String)] = [
            (404, "<!DOCTYPE html><html>Page not found</html>"),
            (401, #"{"success":false}"#),
            (500, ""),
            (200, "<html>a proxy error page</html>"),
            (200, #"["not","an","object"]"#),
        ]
        for (status, body) in replies {
            WelcomeStub.enqueue(body, status: status)
            do {
                _ = try await api.fetchWelcomeText(clientId: "client-1")
                XCTFail("expected a failure for status \(status): \(body.prefix(30))")
            } catch {
                // any failure - the repository treats them all the same way
            }
        }
    }

    // MARK: - the repository and its cache

    func testAGoodReplyIsCachedAndReturned() async {
        WelcomeStub.enqueue(#"{"heading":"Hi","text":"There"}"#)
        let store = MemoryStore()

        let result = await WelcomeTextRepository(apiService: api, clientId: "client-1", store: store).refresh()

        XCTAssertEqual(try? result.get(), WelcomeText(heading: "Hi", text: "There"))
        XCTAssertEqual(store.saved, WelcomeText(heading: "Hi", text: "There"))
    }

    func testAFailureKeepsTheCachedWelcomeSoAFlakyConnectionNeverWipesAWorkingOne() async {
        let store = MemoryStore(WelcomeText(heading: "Cached heading", text: "Cached text"))
        WelcomeStub.enqueue("", status: 404)
        let repository = WelcomeTextRepository(apiService: api, clientId: "client-1", store: store)

        let result = await repository.refresh()

        if case .success = result { XCTFail("a 404 must be a failure") }
        XCTAssertEqual(repository.cached(), WelcomeText(heading: "Cached heading", text: "Cached text"))
    }

    func testTheServerClearingItsWelcomeTextClearsTheCacheSoAStaleOneDoesNotLinger() async {
        let store = MemoryStore(WelcomeText(heading: "Old heading", text: "Old text"))
        WelcomeStub.enqueue(#"{"heading":"","text":""}"#)
        let repository = WelcomeTextRepository(apiService: api, clientId: "client-1", store: store)

        let result = await repository.refresh()

        guard case .success(let value) = result else { return XCTFail("an empty reply is a success, not a failure") }
        XCTAssertNil(value)
        XCTAssertNil(repository.cached())
    }

    // MARK: - how it combines with the host app's own text
    // The branding passed in has already been resolved from the host app's welcomeTitle / welcomeSubtitle
    // (falling back to the theme default) - see Chat360Theme.

    private var hostBranding: Chat360Branding {
        var branding = defaultBranding
        branding.welcomeHeading = "Host heading"
        branding.disclaimerText = "Host subtitle"
        return branding
    }

    func testServerTextWinsOverTheHostAppsText() {
        let result = hostBranding.withWelcome(WelcomeText(heading: "Server heading", text: "Server subtitle"))
        XCTAssertEqual(result.welcomeHeading, "Server heading")
        XCTAssertEqual(result.disclaimerText, "Server subtitle")
    }

    func testNothingFromTheServerLeavesTheHostAppsText() {
        XCTAssertEqual(hostBranding.withWelcome(nil), hostBranding)
        XCTAssertEqual(hostBranding.withWelcome(WelcomeText(heading: nil, text: nil)), hostBranding)
        XCTAssertEqual(hostBranding.withWelcome(WelcomeText(heading: "", text: "  ")), hostBranding)
    }

    func testEachLineFallsBackOnItsOwn() {
        let onlyHeading = hostBranding.withWelcome(WelcomeText(heading: "Server heading", text: nil))
        XCTAssertEqual(onlyHeading.welcomeHeading, "Server heading")
        XCTAssertEqual(onlyHeading.disclaimerText, "Host subtitle")

        let onlyText = hostBranding.withWelcome(WelcomeText(heading: nil, text: "Server subtitle"))
        XCTAssertEqual(onlyText.welcomeHeading, "Host heading")
        XCTAssertEqual(onlyText.disclaimerText, "Server subtitle")
    }

    func testOtherBrandingIsUntouched() {
        var branding = hostBranding
        branding.botTitle = "Custom bot"
        branding.inputPlaceholder = "Ask…"

        let result = branding.withWelcome(WelcomeText(heading: "H", text: "T"))

        XCTAssertEqual(result.botTitle, "Custom bot")
        XCTAssertEqual(result.inputPlaceholder, "Ask…")
    }
}
