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

    // How many rooms the server has handed over so far (the next page's offset), and whether it says
    // there are more. Counted as returned by the server, not as shown: empty rooms are dropped from the
    // list, and a server may cap a page below the size asked for.
    private var loadedCount = 0
    public private(set) var hasMoreRooms = false

    /// Fetches the newest rooms and merges them into the cache; nil on any failure (the caller keeps
    /// showing whatever it already has).
    ///
    /// One request, from the top of the list: a page, or as many rooms as were already loaded so that a
    /// refresh doesn't collapse a list the user had scrolled through. Older rooms come in through
    /// `loadMoreRooms()` instead of being fetched up front.
    public func refreshRooms() async -> [CachedConversationEntity]? {
        do {
            let limit = max(Self.roomsPageSize, loadedCount)
            let page = try await withAuthRetry { token in
                try await self.apiService.fetchRoomsList(bearerToken: token, agentId: self.endUserId, limit: limit, offset: 0)
            }
            loadedCount = page.rooms.count
            hasMoreRooms = page.hasMore && !page.rooms.isEmpty
            await cache.syncLocalConversations(botId: botId, rooms: page.rooms)
            // Replaces the synced rooms: any cached one missing from the top of the list is dropped, and
            // reappears once its page is loaded again.
            let conversations = await cache.thirdPartyRoomConversations(botId: botId, rooms: page.rooms)
            await cache.syncAgentRooms(botId: botId, conversations: conversations)
            return conversations
        } catch {
            NSLog("[Chat360] third-party-tasks rooms/list failed: %@", error.localizedDescription)
            return nil
        }
    }

    static let roomsPageSize = 50

    /// Fetches the next page of older rooms and adds them to the cache. Returns false on failure (the
    /// list is left as it was and the caller can offer a retry); true otherwise, after which
    /// `hasMoreRooms` says whether another page is available.
    public func loadMoreRooms() async -> Bool {
        guard hasMoreRooms else { return true }
        do {
            let offset = loadedCount
            let page = try await withAuthRetry { token in
                try await self.apiService.fetchRoomsList(bearerToken: token, agentId: self.endUserId, limit: Self.roomsPageSize, offset: offset)
            }
            loadedCount += page.rooms.count
            // A page with nothing in it ends the list even if the server still claims more, so a server
            // that misreports has_more can't keep the button alive forever.
            hasMoreRooms = page.hasMore && !page.rooms.isEmpty
            await cache.syncLocalConversations(botId: botId, rooms: page.rooms)
            await cache.mergeAgentRooms(botId: botId, conversations: await cache.thirdPartyRoomConversations(botId: botId, rooms: page.rooms))
            return true
        } catch {
            NSLog("[Chat360] third-party-tasks rooms/list (more) failed: %@", error.localizedDescription)
            return false
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
