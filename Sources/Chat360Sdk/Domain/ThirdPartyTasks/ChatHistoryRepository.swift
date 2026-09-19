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
            // Every page or nothing: the sync below deletes cached rooms that are missing from what it
            // is given, so a fetch that got only the first pages must fail outright rather than hand
            // over a partial list that would wipe the rooms on the pages that never loaded.
            let rooms = try await fetchAllRooms()
            await cache.syncLocalConversations(botId: botId, rooms: rooms)
            let conversations = await cache.thirdPartyRoomConversations(botId: botId, rooms: rooms)
            await cache.syncAgentRooms(botId: botId, conversations: conversations)
            return conversations
        } catch {
            NSLog("[Chat360] third-party-tasks rooms/list failed: %@", error.localizedDescription)
            return nil
        }
    }

    static let roomsPageSize = 100
    static let roomsMaxPages = 50

    // Walks `rooms/list` page by page until the server reports no more. Called with no `limit` the
    // server returns only its default page (20 rooms) and says `has_more`; the list is newest-first
    // and soft-deleted rooms count toward the page, so as deleted and abandoned rooms piled up the
    // real, older chats fell off the end of the history list.
    //
    // The next offset is the number of rooms the server actually returned, not `roomsPageSize`, in
    // case it caps a page lower than asked. Stops early on a page that adds nothing new, so a server
    // that ignores `offset` and repeats one page can't loop forever, and after `roomsMaxPages` as a
    // hard ceiling.
    private func fetchAllRooms() async throws -> [RoomDto] {
        var rooms: [RoomDto] = []
        var seen = Set<String>()
        var offset = 0
        for _ in 0..<Self.roomsMaxPages {
            let currentOffset = offset
            let page = try await withAuthRetry { token in
                try await self.apiService.fetchRoomsList(clientId: self.clientId, bearerToken: token, agentId: self.endUserId, limit: Self.roomsPageSize, offset: currentOffset)
            }
            let fresh = page.rooms.filter { seen.insert($0.roomId).inserted }
            rooms += fresh
            if !page.hasMore || fresh.isEmpty { return rooms }
            offset += page.rooms.count
        }
        NSLog("[Chat360] third-party-tasks rooms/list hit the %d-page ceiling with more still available", Self.roomsMaxPages)
        return rooms
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
