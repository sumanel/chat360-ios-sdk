import Foundation

@available(iOS 13.0, *)
public final class ChatHistoryRepository {
    private let apiService: ThirdPartyTasksApiService
    private let tokenManager: ThirdPartyTokenManager
    private let cache: ChatCacheRepository
    private let clientId: String
    private let botId: String
    private let endUserId: String

    public init(
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

    public func refreshRooms() async -> [CachedConversationEntity]? {
        do {
            let response = try await withAuthRetry { token in
                try await self.apiService.fetchRoomsList(clientId: self.clientId, bearerToken: token, agentId: self.endUserId)
            }
            let conversations = await cache.thirdPartyRoomConversations(botId: botId, rooms: response.rooms)
            await cache.syncAgentRooms(botId: botId, conversations: conversations)
            return conversations
        } catch {
            NSLog("[Chat360] third-party-tasks rooms/list failed: %@", error.localizedDescription)
            return nil
        }
    }

    public func renameRoom(roomId: String, roomName: String) async {
        do {
            _ = try await withAuthRetry { token in
                try await self.apiService.updateRoom(roomId: roomId, clientId: self.clientId, roomName: roomName, bearerToken: token)
            }
        } catch {
            NSLog("[Chat360] third-party-tasks room/update failed: %@", error.localizedDescription)
        }
    }

    public func markRoomInactive(roomId: String) async {
        do {
            _ = try await withAuthRetry { token in
                try await self.apiService.updateRoomStatus(roomId: roomId, clientId: self.clientId, bearerToken: token)
            }
        } catch {
            NSLog("[Chat360] third-party-tasks room/update/status failed: %@", error.localizedDescription)
        }
    }

    public func submitFeedback(roomId: String, sessionId: String, messageId: String, query: String, response: String, feedback: String, remarks: String?) async {
        NSLog(
            "[Chat360] Sending %@ feedback: room=%@ session=%@ message_id=%@ remarks=%@",
            feedback, roomId, sessionId, messageId, remarks ?? "nil"
        )
        do {
            try await withAuthRetry { token in
                try await self.apiService.submitFeedback(
                    roomId: roomId, sessionId: sessionId, messageId: messageId, query: query, response: response,
                    feedback: feedback, remarks: remarks, bearerToken: token
                )
            }
            NSLog("[Chat360] %@ feedback sent successfully (message_id=%@)", feedback, messageId)
        } catch {
            NSLog("[Chat360] third-party-tasks feedback/queries failed: %@", error.localizedDescription)
        }
    }

    public func submitPeriodicFeedback(roomId: String, sessionId: String, feedbackText: String) async {
        do {
            try await withAuthRetry { token in
                try await self.apiService.submitPeriodicFeedback(roomId: roomId, sessionId: sessionId, feedbackText: feedbackText, bearerToken: token)
            }
            NSLog("[Chat360] Periodic feedback sent successfully (room=%@)", roomId)
        } catch {
            NSLog("[Chat360] third-party-tasks feedback failed: %@", error.localizedDescription)
        }
    }

    private func withAuthRetry<T>(_ block: @escaping (String) async throws -> T) async throws -> T {
        let token = try await tokenManager.validToken()
        do {
            return try await block(token)
        } catch let error as ThirdPartyHttpException {
            guard error.httpCode == 401 else { throw error }
            await tokenManager.invalidate()
            let refreshed = try await tokenManager.validToken()
            return try await block(refreshed)
        }
    }
}
