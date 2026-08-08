import Foundation

/// Queues canned `(statusCode, body)` responses for `URLProtocol`-intercepted requests - the
/// standard way to test `URLSession`-based network code without a real server. Records each
/// request's `Authorization` header so callers can assert which bearer token was actually sent.
final class StubURLProtocol: URLProtocol {
    struct StubResponse {
        let statusCode: Int
        let body: String
    }

    private static let queue = DispatchQueue(label: "com.chat360.stubURLProtocol")
    private static var responses: [StubResponse] = []
    private static var _recordedAuthorizationHeaders: [String?] = []

    static var recordedAuthorizationHeaders: [String?] { queue.sync { _recordedAuthorizationHeaders } }
    static var requestCount: Int { queue.sync { _recordedAuthorizationHeaders.count } }

    static func enqueue(statusCode: Int, body: String) {
        queue.sync { responses.append(StubResponse(statusCode: statusCode, body: body)) }
    }

    static func reset() {
        queue.sync {
            responses = []
            _recordedAuthorizationHeaders = []
        }
    }

    static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: config)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let stub: StubResponse? = Self.queue.sync {
            Self._recordedAuthorizationHeaders.append(request.value(forHTTPHeaderField: "Authorization"))
            return Self.responses.isEmpty ? nil : Self.responses.removeFirst()
        }
        guard let stub, let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        let response = HTTPURLResponse(url: url, statusCode: stub.statusCode, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(stub.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
