import Foundation

/// Backs the rooms/conversations list with the third-party-tasks API family. Every method is
/// best-effort: on failure the existing `ChatCacheRepository` contents are left untouched and the
/// error is only logged - these calls must never surface an error to the user or affect the live
/// chat/bot flow.
///
/// `clientId`, `botId`, and `endUserId` must all be non-empty - there is intentionally no
/// partially-configured mode: history is either fully identified or fully off.
final class ChatHistoryRepository {
    private let apiService: ThirdPartyTasksApiService
    private let tokenManager: ThirdPartyTokenManager
    private let cache: ChatCacheRepository
    private let clientId: String
    private let botId: String
    /// The current end user's identity - scopes `rooms/list` to their rooms. Sent on the wire as
    /// the `agent_id` query parameter (the backend's own naming - see `ThirdPartyTasksApiService`).
    /// Required - see type doc.
    private let endUserId: String

    init(
        apiService: ThirdPartyTasksApiService,
        tokenManager: ThirdPartyTokenManager,
        cache: ChatCacheRepository,
        clientId: String,
        botId: String,
        endUserId: String
    ) {
        self.apiService = apiService
        self.tokenManager = tokenManager
        self.cache = cache
        self.clientId = clientId
        self.botId = botId
        self.endUserId = endUserId
    }

    /// Fetches the rooms list and merges it into the cache. Callers should re-read
    /// `cache.conversations(botId:)` afterward - failure leaves whatever's cached untouched.
    /// Returns whether the fetch succeeded, so callers can distinguish "fetch failed" from
    /// "fetch succeeded with zero rooms" (see `ChatUiState.isHistoryUnavailable`).
    @discardableResult
    func refreshRooms() async -> Bool {
        do {
            let response = try await withAuthRetry { token in
                try await self.apiService.fetchRoomsList(clientId: self.clientId, bearerToken: token, botId: self.botId, agentId: self.endUserId)
            }
            cache.syncThirdPartyRooms(botId: botId, rooms: response.rooms)
            return true
        } catch {
            print("[Chat360] third-party-tasks rooms/list failed: \(error)")
            return false
        }
    }

    /// Fetches one room's message history from `third-party-tasks/chat/history` and seeds the
    /// cache with it. Best-effort like `refreshRooms()` - a failure just leaves the conversation's
    /// cache empty rather than surfacing an error, since this only ever runs when the cache already
    /// had nothing to show.
    @discardableResult
    func fetchChatHistory(conversationId: String, roomId: String, sessionId: String) async -> Bool {
        do {
            let response = try await withAuthRetry { token in
                try await self.apiService.fetchChatHistory(roomId: roomId, sessionId: sessionId, bearerToken: token)
            }
            cache.replaceThirdPartyHistory(conversationId: conversationId, messages: response.messages)
            return !response.messages.isEmpty
        } catch {
            print("[Chat360] third-party-tasks chat/history failed: \(error)")
            return false
        }
    }

    /// Best-effort remote rename - failure never blocks the local rename the caller already applied.
    func renameRoom(roomId: String, roomName: String) async {
        do {
            _ = try await withAuthRetry { token in
                try await self.apiService.updateRoom(roomId: roomId, clientId: self.clientId, roomName: roomName, bearerToken: token)
            }
        } catch {
            print("[Chat360] third-party-tasks room/update failed: \(error)")
        }
    }

    /// Best-effort remote "mark inactive" - the counterpart of deleting a conversation from history.
    func markRoomInactive(roomId: String) async {
        do {
            _ = try await withAuthRetry { token in
                try await self.apiService.updateRoomStatus(roomId: roomId, clientId: self.clientId, bearerToken: token)
            }
        } catch {
            print("[Chat360] third-party-tasks room/update/status failed: \(error)")
        }
    }

    private func withAuthRetry<T>(_ block: @escaping (String) async throws -> T) async throws -> T {
        let token = try await tokenManager.validToken()
        do {
            return try await block(token)
        } catch Chat360ApiError.httpError(let code, _) where code == 401 {
            await tokenManager.invalidate()
            let refreshed = try await tokenManager.validToken()
            return try await block(refreshed)
        }
    }
}
