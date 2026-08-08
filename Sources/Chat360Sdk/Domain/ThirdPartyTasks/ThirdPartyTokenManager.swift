import Foundation

/// Caches the third-party-tasks bearer token in memory with an expiry derived from `expires_in`
/// (not the server's `issued_at`, to avoid clock-skew parsing). A 60s safety margin refreshes
/// slightly ahead of actual expiry so an in-flight rooms-list call doesn't race a stale token.
///
/// `fetchToken` is a closure, not a concrete `ThirdPartyTasksApiService` - tests can supply a fake
/// without a real network client; the convenience `init` covers production callers.
actor ThirdPartyTokenManager {
    private let fetchToken: () async throws -> TokenResponse

    private var cachedToken: String?
    private var expiresAt: Date = .distantPast
    /// The single fetch currently in flight, if any - actor methods are reentrant across `await`
    /// suspension points in Swift, so without this, N concurrent `validToken()` callers arriving
    /// before the first fetch completes would each see `cachedToken == nil` and independently
    /// trigger their own `fetchToken()`. Every concurrent caller instead awaits this same task.
    private var inFlightRefresh: Task<String, Error>?

    /// Test seam - defaults to the real wall clock.
    private let now: () -> Date

    private static let safetyMargin: TimeInterval = 60

    init(fetchToken: @escaping () async throws -> TokenResponse, now: @escaping () -> Date = Date.init) {
        self.fetchToken = fetchToken
        self.now = now
    }

    init(apiService: ThirdPartyTasksApiService, clientId: String, apiKey: String) {
        self.init(fetchToken: { try await apiService.fetchToken(clientId: clientId, apiKey: apiKey) })
    }

    func validToken() async throws -> String {
        if let token = cachedToken, now() < expiresAt { return token }
        if let inFlightRefresh { return try await inFlightRefresh.value }
        let task = Task { try await self.refreshToken() }
        inFlightRefresh = task
        defer { inFlightRefresh = nil }
        return try await task.value
    }

    private func refreshToken() async throws -> String {
        let response = try await fetchToken()
        cachedToken = response.bearer_token
        expiresAt = now().addingTimeInterval(TimeInterval(response.expires_in) - Self.safetyMargin)
        return response.bearer_token
    }

    /// Forces the next `validToken()` call to refetch - used after a 401 from a room call.
    func invalidate() {
        cachedToken = nil
        expiresAt = .distantPast
    }
}
