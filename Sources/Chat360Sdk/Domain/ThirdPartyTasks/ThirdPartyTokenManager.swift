import Foundation

@available(iOS 13.0, *)
public actor ThirdPartyTokenManager {
    private static let safetyMarginMs: Int64 = 60_000

    private let fetchToken: () async throws -> TokenResponse
    private let nowMillis: () -> Int64
    private var cachedToken: String?
    private var expiresAtMillis: Int64 = 0

    public init(fetchToken: @escaping () async throws -> TokenResponse, nowMillis: @escaping () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1000) }) {
        self.fetchToken = fetchToken
        self.nowMillis = nowMillis
    }

    public init(apiService: ThirdPartyTasksApiService, clientId: String, apiKey: String) {
        self.init(fetchToken: { try await apiService.fetchToken(clientId: clientId, apiKey: apiKey) })
    }

    public func validToken() async throws -> String {
        if let token = cachedToken, nowMillis() < expiresAtMillis {
            return token
        }
        let response = try await fetchToken()
        cachedToken = response.bearerToken
        expiresAtMillis = nowMillis() + (response.expiresIn * 1000) - Self.safetyMarginMs
        return response.bearerToken
    }

    public func invalidate() {
        cachedToken = nil
        expiresAtMillis = 0
    }
}
