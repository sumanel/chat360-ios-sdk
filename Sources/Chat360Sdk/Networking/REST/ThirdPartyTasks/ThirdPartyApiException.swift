import Foundation

public struct ThirdPartyHttpException: Error {
    public let httpCode: Int
    public let url: String

    public init(httpCode: Int, url: String) {
        self.httpCode = httpCode
        self.url = url
    }

    public var localizedDescription: String { "HTTP \(httpCode) for \(url)" }
}

public struct ThirdPartyMalformedResponseException: Error {
    public let endpoint: String

    public init(endpoint: String) {
        self.endpoint = endpoint
    }

    public var localizedDescription: String { "third-party-tasks \(endpoint) returned a successful response with no data" }
}
