import Foundation

public struct ConversationSummary: Equatable {
    public let id: String
    public let title: String
    public let updatedAt: Int64

    public init(id: String, title: String, updatedAt: Int64) {
        self.id = id
        self.title = title
        self.updatedAt = updatedAt
    }
}

@available(iOS 13.0, *)
public final class ChatCacheRepository {
    public static let enabled = true

    private let dao: ChatCacheDao
    private let encoder = JSONEncoder()

    public init(dao: ChatCacheDao) {
        self.dao = dao
    }

    public func conversations(botId: String) -> AsyncStream<[CachedConversationEntity]> {
        guard Self.enabled else {
            return AsyncStream { continuation in
                continuation.finish()
            }
        }
        return dao.observeConversations(botId: botId)
    }

    public func activateForRoom(botId: String, roomId: String, pendingId: String?) async -> (String, Bool) {
        guard Self.enabled else { return (pendingId ?? UUID().uuidString, false) }
        if let existing = await dao.findConversation(botId: botId, roomId: roomId) {
            await dao.setRoom(conversationId: existing.id, roomId: roomId, updatedAt: nowMs(), botId: botId)
            let hasMessages = await !dao.messages(conversationId: existing.id).isEmpty
            return (existing.id, hasMessages)
        }
        return (pendingId ?? UUID().uuidString, false)
    }

    public func ensureConversationPersisted(botId: String, conversationId: String, roomId: String?) async {
        guard Self.enabled else { return }
        let now = nowMs()
        await dao.insertConversationIfMissing(CachedConversationEntity(id: conversationId, botId: botId, roomId: roomId, createdAt: now, updatedAt: now))
        if let roomId {
            await dao.setRoom(conversationId: conversationId, roomId: roomId, updatedAt: now, botId: botId)
        }
    }

    public func messages(conversationId: String) async -> [CachedMessageEntity] {
        guard Self.enabled else { return [] }
        return await dao.messages(conversationId: conversationId)
    }

    public func syncAgentRooms(botId: String, conversations: [CachedConversationEntity]) async {
        guard Self.enabled else { return }
        await dao.replaceAgentRoomConversations(botId: botId, conversations: conversations)
    }

    public func thirdPartyRoomConversations(botId: String, rooms: [RoomDto]) -> [CachedConversationEntity] {
        let fetchedAt = nowMs()
        return rooms.enumerated().compactMap { index, room -> CachedConversationEntity? in
            if room.status?.caseInsensitiveCompare("inactive") == .orderedSame { return nil }
            // A room the server created but the user never actually sent anything in has no
            // sessions yet - it has no title either, so it'd otherwise show up as a blank
            // "Conversation" entry in history despite nothing having happened in it.
            if room.sessionCount <= 0 { return nil }
            let title = room.roomName.trimmingCharacters(in: .whitespacesAndNewlines)
            return CachedConversationEntity(
                id: "agent-room:\(room.roomId)",
                botId: botId,
                roomId: room.roomId,
                title: title.isEmpty ? "Conversation" : title,
                createdAt: fetchedAt - Int64(index),
                updatedAt: fetchedAt - Int64(index)
            )
        }
    }

    public func replaceRawHistory(conversationId: String, history: [RawSocketEnvelope]) async {
        guard Self.enabled else { return }
        let fetchedAt = nowMs()
        let messages = history.enumerated().compactMap { index, envelope -> CachedMessageEntity? in
            guard let data = try? encoder.encode(envelope), let payload = String(data: data, encoding: .utf8) else { return nil }
            return CachedMessageEntity(conversationId: conversationId, kind: "RAW", payload: payload, createdAt: fetchedAt + Int64(index))
        }
        await dao.replaceMessages(conversationId: conversationId, messages: messages)
    }

    public func renameConversation(conversationId: String, title: String, botId: String) async {
        guard Self.enabled else { return }
        await dao.updateTitle(conversationId: conversationId, title: title, botId: botId)
    }

    public func deleteConversation(conversationId: String, botId: String) async {
        guard Self.enabled else { return }
        await dao.deleteConversation(conversationId: conversationId, botId: botId)
    }

    public func cacheRaw(conversationId: String, rawEnvelope: String, botId: String) async {
        guard Self.enabled else { return }
        let now = nowMs()
        await dao.insertMessage(CachedMessageEntity(conversationId: conversationId, kind: "RAW", payload: rawEnvelope, createdAt: now))
        await dao.touch(conversationId: conversationId, updatedAt: now, botId: botId)
    }

    public func cacheUserMessage(conversationId: String, text: String, chatMsgId: String?, botId: String) async {
        guard Self.enabled else { return }
        let now = nowMs()
        await dao.insertMessage(CachedMessageEntity(conversationId: conversationId, kind: "USER", payload: text, chatMsgId: chatMsgId, createdAt: now))
        let title = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        let truncated = String(title.prefix(80))
        if !truncated.isBlank {
            await dao.touchAndSetTitleIfUnset(conversationId: conversationId, title: truncated, updatedAt: now, botId: botId)
        } else {
            await dao.touch(conversationId: conversationId, updatedAt: now, botId: botId)
        }
    }

    public func markFeedbackPending(messageId: String, conversationId: String) async {
        guard Self.enabled else { return }
        await dao.insertPendingFeedbackIfMissing(messageId: messageId, conversationId: conversationId, createdAt: nowMs())
    }

    public func pendingFeedbackMessageIds(conversationId: String) async -> [String] {
        guard Self.enabled else { return [] }
        return await dao.pendingFeedbackMessageIds(conversationId: conversationId)
    }

    public func clearPendingFeedback(messageId: String) async {
        guard Self.enabled else { return }
        await dao.deletePendingFeedback(messageId: messageId)
    }

    public func setMessageReaction(conversationId: String, timestampMs: Int64, liked: Bool) async {
        guard Self.enabled else { return }
        await dao.setMessageReaction(conversationId: conversationId, timestampMs: timestampMs, liked: liked)
    }

    public func messageReactions(conversationId: String) async -> [Int64: Bool] {
        guard Self.enabled else { return [:] }
        return await dao.messageReactions(conversationId: conversationId)
    }

    private func nowMs() -> Int64 {
        Int64(Date().timeIntervalSince1970 * 1000)
    }
}
