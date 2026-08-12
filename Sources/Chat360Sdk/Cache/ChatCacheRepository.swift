import Foundation
import Combine
import SQLite3

/// Local conversation-history cache. Thin wrapper around `ChatCacheDatabase`: almost pure
/// pass-through SQL, plus id generation and the title-from-first-message heuristic. Deliberately
/// synchronous (SQLite on a small local file is fast) rather than `async`, so `cacheRaw` can be
/// called durably from a WebSocket callback thread without depending on a `Task`'s lifetime.
final class ChatCacheRepository {
    static let shared = ChatCacheRepository(database: .shared)

    private let database: ChatCacheDatabase
    /// Fires after any write that could change the conversation list (create/rename/touch/delete)
    /// - callers re-query `conversations(botId:)` in response. SQLite has no built-in push
    /// mechanism for query invalidation, so this is the explicit substitute.
    let conversationsChanged = PassthroughSubject<Void, Never>()

    init(database: ChatCacheDatabase) {
        self.database = database
    }

    // MARK: Conversations

    func conversations(botId: String) -> [CachedConversation] {
        database.perform { db in
            guard let stmt = sqlitePrepare(db, "SELECT id, botId, roomId, sessionId, title, createdAt, updatedAt FROM chat_conversations WHERE botId = ? ORDER BY updatedAt DESC", [botId]) else { return [] }
            defer { sqlite3_finalize(stmt) }
            var results: [CachedConversation] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                results.append(CachedConversation(
                    id: sqliteColumnText(stmt, 0) ?? "",
                    botId: sqliteColumnText(stmt, 1) ?? "",
                    roomId: sqliteColumnText(stmt, 2),
                    sessionId: sqliteColumnText(stmt, 3),
                    title: sqliteColumnText(stmt, 4) ?? "New conversation",
                    createdAt: sqlite3_column_int64(stmt, 5),
                    updatedAt: sqlite3_column_int64(stmt, 6)
                ))
            }
            return results
        }
    }

    @discardableResult
    func createConversation(botId: String, id: String = UUID().uuidString) -> String {
        let now = Self.now()
        database.perform { db in
            let stmt = sqlitePrepare(db, """
                INSERT OR REPLACE INTO chat_conversations (id, botId, roomId, title, createdAt, updatedAt)
                VALUES (?, ?, NULL, 'New conversation', ?, ?)
                """, [id, botId, now, now])
            defer { if let stmt { sqlite3_finalize(stmt) } }
            _ = stmt.map { sqlite3_step($0) }
        }
        conversationsChanged.send()
        return id
    }

    /// Looks up (or creates) the local conversation for a server `roomId`, binds them together,
    /// and reports whether that conversation already has cached messages to replay - callers fall
    /// back to a network history fetch only when this is `false`.
    func activateForRoom(botId: String, roomId: String, pendingId: String?) -> (id: String, hasCachedMessages: Bool) {
        let existingId: String? = database.perform { db in
            guard let stmt = sqlitePrepare(db, "SELECT id FROM chat_conversations WHERE botId = ? AND roomId = ? LIMIT 1", [botId, roomId]) else { return nil }
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
            return sqliteColumnText(stmt, 0)
        }
        let id = existingId ?? pendingId ?? createConversation(botId: botId)
        let now = Self.now()
        database.perform { db in
            let stmt = sqlitePrepare(db, "UPDATE chat_conversations SET roomId = ?, updatedAt = ? WHERE id = ?", [roomId, now, id])
            defer { if let stmt { sqlite3_finalize(stmt) } }
            _ = stmt.map { sqlite3_step($0) }
        }
        conversationsChanged.send()
        return (id, !messages(conversationId: id).isEmpty)
    }

    /// Merges the third-party-tasks `rooms/list` result into the cache: every `tp-room:`-prefixed
    /// row from the previous fetch is added, updated, or removed to match the new response, so
    /// the cache always reflects the latest server state rather than accumulating stale rooms.
    /// Rooms already marked inactive (soft-deleted via `room/update/status`) are dropped so a
    /// background refresh can't resurrect a conversation the user just deleted.
    func syncThirdPartyRooms(botId: String, rooms: [RoomDto]) {
        let fetchedAt = Self.now()
        let active = rooms.filter { !($0.status?.caseInsensitiveCompare("inactive") == .orderedSame) }
        let refreshedIds = Set(active.map { "tp-room:\($0.room_id)" })
        database.perform { db in
            _ = sqlite3_exec(db, "BEGIN IMMEDIATE TRANSACTION;", nil, nil, nil)
            if let stmt = sqlitePrepare(db, "SELECT id FROM chat_conversations WHERE botId = ? AND id LIKE 'tp-room:%'", [botId]) {
                var staleIds: [String] = []
                while sqlite3_step(stmt) == SQLITE_ROW {
                    if let id = sqliteColumnText(stmt, 0), !refreshedIds.contains(id) { staleIds.append(id) }
                }
                sqlite3_finalize(stmt)
                for staleId in staleIds {
                    if let deleteStmt = sqlitePrepare(db, "DELETE FROM chat_conversations WHERE id = ?", [staleId]) {
                        _ = sqlite3_step(deleteStmt)
                        sqlite3_finalize(deleteStmt)
                    }
                }
            }
            for (index, room) in active.enumerated() {
                let id = "tp-room:\(room.room_id)"
                let title = room.room_name.trimmingCharacters(in: .whitespacesAndNewlines)
                let displayTitle = title.isEmpty ? "Conversation" : title
                let updatedAt = fetchedAt - Int64(index)
                // The most recent session is the one `chat/history` should be fetched against if
                // this room has no cached messages yet - the server doesn't offer a way to fetch
                // history spanning multiple sessions in one call.
                let sessionId = room.session_ids.last
                if let insertStmt = sqlitePrepare(db, """
                    INSERT OR IGNORE INTO chat_conversations (id, botId, roomId, sessionId, title, createdAt, updatedAt)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                    """, [id, botId, room.room_id, sessionId, displayTitle, updatedAt, updatedAt]) {
                    _ = sqlite3_step(insertStmt)
                    sqlite3_finalize(insertStmt)
                }
                if let updateStmt = sqlitePrepare(db, """
                    UPDATE chat_conversations SET roomId = ?, sessionId = ?, title = ?, updatedAt = ? WHERE id = ?
                    """, [room.room_id, sessionId, displayTitle, updatedAt, id]) {
                    _ = sqlite3_step(updateStmt)
                    sqlite3_finalize(updateStmt)
                }
            }
            _ = sqlite3_exec(db, "COMMIT;", nil, nil, nil)
        }
        conversationsChanged.send()
    }

    func renameConversation(conversationId: String, title: String) {
        let now = Self.now()
        database.perform { db in
            let stmt = sqlitePrepare(db, "UPDATE chat_conversations SET title = ?, updatedAt = ? WHERE id = ?", [title, now, conversationId])
            defer { if let stmt { sqlite3_finalize(stmt) } }
            _ = stmt.map { sqlite3_step($0) }
        }
        conversationsChanged.send()
    }

    func deleteConversation(conversationId: String) {
        database.perform { db in
            let stmt = sqlitePrepare(db, "DELETE FROM chat_conversations WHERE id = ?", [conversationId])
            defer { if let stmt { sqlite3_finalize(stmt) } }
            _ = stmt.map { sqlite3_step($0) }
        }
        conversationsChanged.send()
    }

    private func touch(_ conversationId: String) {
        let now = Self.now()
        database.perform { db in
            let stmt = sqlitePrepare(db, "UPDATE chat_conversations SET updatedAt = ? WHERE id = ?", [now, conversationId])
            defer { if let stmt { sqlite3_finalize(stmt) } }
            _ = stmt.map { sqlite3_step($0) }
        }
        conversationsChanged.send()
    }

    // MARK: Messages

    func messages(conversationId: String) -> [CachedMessage] {
        database.perform { db in
            guard let stmt = sqlitePrepare(db, "SELECT id, conversationId, kind, payload, chatMsgId, createdAt FROM chat_messages WHERE conversationId = ? ORDER BY id ASC", [conversationId]) else { return [] }
            defer { sqlite3_finalize(stmt) }
            var results: [CachedMessage] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                let kindRaw = sqliteColumnText(stmt, 2) ?? CachedMessageKind.raw.rawValue
                results.append(CachedMessage(
                    id: sqlite3_column_int64(stmt, 0),
                    conversationId: sqliteColumnText(stmt, 1) ?? conversationId,
                    kind: CachedMessageKind(rawValue: kindRaw) ?? .raw,
                    payload: sqliteColumnText(stmt, 3) ?? "",
                    chatMsgId: sqliteColumnText(stmt, 4),
                    createdAt: sqlite3_column_int64(stmt, 5)
                ))
            }
            return results
        }
    }

    /// Delete-then-insert, wrapped in one transaction for atomicity. Used to seed a conversation's
    /// cache from a freshly-fetched network history page.
    func replaceRawHistory(conversationId: String, rawEnvelopes: [String]) {
        let fetchedAt = Self.now()
        database.perform { db in
            _ = sqlite3_exec(db, "BEGIN IMMEDIATE TRANSACTION;", nil, nil, nil)
            let deleteStmt = sqlitePrepare(db, "DELETE FROM chat_messages WHERE conversationId = ?", [conversationId])
            if let deleteStmt { _ = sqlite3_step(deleteStmt); sqlite3_finalize(deleteStmt) }
            for (index, envelope) in rawEnvelopes.enumerated() {
                let insertStmt = sqlitePrepare(db, """
                    INSERT INTO chat_messages (conversationId, kind, payload, chatMsgId, createdAt) VALUES (?, ?, ?, NULL, ?)
                    """, [conversationId, CachedMessageKind.raw.rawValue, envelope, fetchedAt + Int64(index)])
                if let insertStmt { _ = sqlite3_step(insertStmt); sqlite3_finalize(insertStmt) }
            }
            _ = sqlite3_exec(db, "COMMIT;", nil, nil, nil)
        }
    }

    /// Delete-then-insert, wrapped in one transaction for atomicity. Seeds a `tp-room:` conversation
    /// from a freshly-fetched `third-party-tasks/chat/history` page - the counterpart of
    /// `replaceRawHistory` for that flat, non-websocket message shape.
    func replaceThirdPartyHistory(conversationId: String, messages: [ChatHistoryMessage]) {
        let fetchedAt = Self.now()
        let encoder = JSONEncoder()
        database.perform { db in
            _ = sqlite3_exec(db, "BEGIN IMMEDIATE TRANSACTION;", nil, nil, nil)
            let deleteStmt = sqlitePrepare(db, "DELETE FROM chat_messages WHERE conversationId = ?", [conversationId])
            if let deleteStmt { _ = sqlite3_step(deleteStmt); sqlite3_finalize(deleteStmt) }
            for (index, message) in messages.enumerated() {
                guard let data = try? encoder.encode(message), let payload = String(data: data, encoding: .utf8) else { continue }
                let insertStmt = sqlitePrepare(db, """
                    INSERT INTO chat_messages (conversationId, kind, payload, chatMsgId, createdAt) VALUES (?, ?, ?, ?, ?)
                    """, [conversationId, CachedMessageKind.thirdPartyHistory.rawValue, payload, message.message_id, fetchedAt + Int64(index)])
                if let insertStmt { _ = sqlite3_step(insertStmt); sqlite3_finalize(insertStmt) }
            }
            _ = sqlite3_exec(db, "COMMIT;", nil, nil, nil)
        }
    }

    /// Appends one raw envelope as it arrives live, and bumps the conversation's `updatedAt`.
    /// Deliberately synchronous (see type doc) - safe to call from a WebSocket delivery thread.
    func cacheRaw(conversationId: String, raw: String) {
        let now = Self.now()
        database.perform { db in
            let stmt = sqlitePrepare(db, "INSERT INTO chat_messages (conversationId, kind, payload, chatMsgId, createdAt) VALUES (?, ?, ?, NULL, ?)", [conversationId, CachedMessageKind.raw.rawValue, raw, now])
            defer { if let stmt { sqlite3_finalize(stmt) } }
            _ = stmt.map { sqlite3_step($0) }
        }
        touch(conversationId)
    }

    /// Appends a locally-authored user message and derives the conversation's title from it (the
    /// first 80 chars, whitespace-collapsed).
    func cacheUserMessage(conversationId: String, text: String, chatMsgId: String?) {
        let now = Self.now()
        database.perform { db in
            let stmt = sqlitePrepare(db, "INSERT INTO chat_messages (conversationId, kind, payload, chatMsgId, createdAt) VALUES (?, ?, ?, ?, ?)", [conversationId, CachedMessageKind.user.rawValue, text, chatMsgId, now])
            defer { if let stmt { sqlite3_finalize(stmt) } }
            _ = stmt.map { sqlite3_step($0) }
        }
        let title = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        let truncated = String(title.prefix(80))
        if !truncated.isEmpty {
            renameConversation(conversationId: conversationId, title: truncated)
        } else {
            touch(conversationId)
        }
    }

    private static func now() -> Int64 {
        Int64(Date().timeIntervalSince1970 * 1000)
    }
}
