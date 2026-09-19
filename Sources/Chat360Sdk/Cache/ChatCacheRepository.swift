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

    /// Applies what the server says about rooms this device already has a local conversation for:
    /// a room the server marks inactive (deleted elsewhere) is removed here too, and a name the
    /// server holds replaces a differing local title. Without this the local row - which owns the
    /// room and so shields it from the `agent-room:` sync - never changed after it was created.
    /// Call only with a complete rooms list.
    public func syncLocalConversations(botId: String, rooms: [RoomDto]) async {
        guard Self.enabled else { return }
        for room in rooms {
            guard let local = await dao.findConversation(botId: botId, roomId: room.roomId),
                  !local.id.hasPrefix("agent-room:") else { continue }
            if room.status?.caseInsensitiveCompare("inactive") == .orderedSame {
                await dao.deleteMessages(conversationId: local.id)
                await dao.deleteConversation(conversationId: local.id, botId: botId)
                continue
            }
            let name = room.roomName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty && name != local.title {
                await dao.updateTitle(conversationId: local.id, title: name, botId: botId)
            }
        }
    }

    public func thirdPartyRoomConversations(botId: String, rooms: [RoomDto]) async -> [CachedConversationEntity] {
        guard Self.enabled else { return [] }
        let fetchedAt = nowMs()
        var result: [CachedConversationEntity] = []
        for (index, room) in rooms.enumerated() {
            if room.status?.caseInsensitiveCompare("inactive") == .orderedSame { continue }
            // Nobody typed in it: a server session_count of 0 is an empty room. A room the server gives
            // neither a name nor a count for is treated the same (an abandoned one). An unnamed room
            // that does have sessions is a real chat and is listed as "Conversation". Checked against
            // the live rooms list: count > 0 held for exactly the rooms holding a user message.
            if room.sessionCount == 0 { continue }
            if room.sessionCount == nil && room.roomName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }
            let title = room.roomName.trimmingCharacters(in: .whitespacesAndNewlines)
            // The server's own timestamps drive the sidebar order - the response position is only
            // a fallback for a room that carries none, so order never depends on API ordering.
            let positional = fetchedAt - Int64(index)
            let created = Self.parseServerTimestampMs(room.createdAt)
            let updated = Self.parseServerTimestampMs(room.updatedAt) ?? created
            result.append(CachedConversationEntity(
                id: "agent-room:\(room.roomId)",
                botId: botId,
                roomId: room.roomId,
                title: title.isEmpty ? "Conversation" : title,
                createdAt: created ?? positional,
                updatedAt: updated ?? positional
            ))
        }
        // Newest first regardless of the order the server returned the rooms in.
        return result.sorted { $0.updatedAt > $1.updatedAt }
    }

    /// Parses a `rooms/list` timestamp - epoch seconds/millis or ISO-8601 (with or without
    /// fractional seconds / zone) - to epoch millis; nil when absent or unrecognised.
    static func parseServerTimestampMs(_ raw: String?) -> Int64? {
        guard let value = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        if let number = Double(value) {
            // Below ~1e11 it can only be seconds (that's year 5138 in millis).
            return number < 1e11 ? Int64(number * 1000) : Int64(number)
        }
        // Trim fractional seconds to millis and make the zone `+HHmm` so one pattern set fits all.
        var normalized = value.replacingOccurrences(of: "(\\.\\d{3})\\d+", with: "$1", options: .regularExpression)
        normalized = normalized.replacingOccurrences(of: "Z$", with: "+0000", options: .regularExpression)
        normalized = normalized.replacingOccurrences(of: "([+-]\\d{2}):(\\d{2})$", with: "$1$2", options: .regularExpression)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        // Zone-less values are treated as UTC, the usual server default.
        formatter.timeZone = TimeZone(identifier: "UTC")
        let patterns = [
            "yyyy-MM-dd'T'HH:mm:ss.SSSZ", "yyyy-MM-dd'T'HH:mm:ssZ",
            "yyyy-MM-dd HH:mm:ss.SSSZ", "yyyy-MM-dd HH:mm:ssZ",
            "yyyy-MM-dd'T'HH:mm:ss.SSS", "yyyy-MM-dd'T'HH:mm:ss",
            "yyyy-MM-dd HH:mm:ss.SSS", "yyyy-MM-dd HH:mm:ss",
        ]
        for pattern in patterns {
            formatter.dateFormat = pattern
            if let date = formatter.date(from: normalized) { return Int64((date.timeIntervalSince1970 * 1000).rounded()) }
        }
        return nil
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

    public func markFeedbackPending(messageId: String, conversationId: String, timestampMs: Int64?) async {
        guard Self.enabled else { return }
        await dao.insertPendingFeedbackIfMissing(messageId: messageId, conversationId: conversationId, timestampMs: timestampMs, createdAt: nowMs())
    }

    public func pendingFeedbackEntries(conversationId: String) async -> [PendingFeedbackEntity] {
        guard Self.enabled else { return [] }
        return await dao.pendingFeedbackEntries(conversationId: conversationId)
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

    public func clearMessageReaction(conversationId: String, timestampMs: Int64) async {
        guard Self.enabled else { return }
        await dao.deleteMessageReaction(conversationId: conversationId, timestampMs: timestampMs)
    }

    public func markReplyPending(conversationId: String, chatMsgId: String?) async {
        guard Self.enabled else { return }
        await dao.markReplyPending(conversationId: conversationId, chatMsgId: chatMsgId, createdAt: nowMs())
    }

    public func replyPending(conversationId: String) async -> ReplyPendingEntity? {
        guard Self.enabled else { return nil }
        return await dao.replyPending(conversationId: conversationId)
    }

    public func clearReplyPending(conversationId: String) async {
        guard Self.enabled else { return }
        await dao.clearReplyPending(conversationId: conversationId)
    }

    public func setSuppressedOpenerNodeIdIfMissing(conversationId: String, nodeId: String) async {
        guard Self.enabled else { return }
        await dao.setSuppressedOpenerNodeIdIfMissing(conversationId: conversationId, nodeId: nodeId)
    }

    public func suppressedOpenerNodeId(conversationId: String) async -> String? {
        guard Self.enabled else { return nil }
        return await dao.suppressedOpenerNodeId(conversationId: conversationId)
    }

    public func setSessionCreatedAt(conversationId: String, createdAtMs: Int64) async {
        guard Self.enabled else { return }
        await dao.setSessionCreatedAt(conversationId: conversationId, createdAtMs: createdAtMs)
    }

    public func sessionCreatedAt(conversationId: String) async -> Int64? {
        guard Self.enabled else { return nil }
        return await dao.sessionCreatedAt(conversationId: conversationId)
    }

    private func nowMs() -> Int64 {
        Int64(Date().timeIntervalSince1970 * 1000)
    }
}
