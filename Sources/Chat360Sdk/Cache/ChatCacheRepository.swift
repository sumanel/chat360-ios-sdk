import Foundation
import Combine
import SQLite3

/// Local conversation-history cache - the Swift port of Android's `ChatCacheRepository`. Thin
/// wrapper around `ChatCacheDatabase`: almost pure pass-through SQL, plus id generation and the
/// title-from-first-message heuristic. Deliberately synchronous (SQLite on a small local file is
/// fast) rather than `async`, so `cacheRaw` can be called durably from a WebSocket callback thread
/// without depending on a `Task`'s lifetime.
final class ChatCacheRepository {
    static let shared = ChatCacheRepository(database: .shared)

    private let database: ChatCacheDatabase
    /// Fires after any write that could change the conversation list (create/rename/touch/delete)
    /// - callers re-query `conversations(botId:)` in response. Mirrors what Room's
    /// `Flow<List<...>>` auto-invalidation gives Android for free; SQLite has no such push
    /// mechanism, so this is the explicit substitute.
    let conversationsChanged = PassthroughSubject<Void, Never>()

    init(database: ChatCacheDatabase) {
        self.database = database
    }

    // MARK: Conversations

    func conversations(botId: String) -> [CachedConversation] {
        database.perform { db in
            guard let stmt = sqlitePrepare(db, "SELECT id, botId, roomId, title, createdAt, updatedAt FROM chat_conversations WHERE botId = ? ORDER BY updatedAt DESC", [botId]) else { return [] }
            defer { sqlite3_finalize(stmt) }
            var results: [CachedConversation] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                results.append(CachedConversation(
                    id: sqliteColumnText(stmt, 0) ?? "",
                    botId: sqliteColumnText(stmt, 1) ?? "",
                    roomId: sqliteColumnText(stmt, 2),
                    title: sqliteColumnText(stmt, 3) ?? "New conversation",
                    createdAt: sqlite3_column_int64(stmt, 4),
                    updatedAt: sqlite3_column_int64(stmt, 5)
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

    /// Delete-then-insert, wrapped in one transaction for atomicity (Room's
    /// `@Transaction`-annotated `replaceMessages` equivalent). Used to seed a conversation's cache
    /// from a freshly-fetched network history page.
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
    /// first 80 chars, whitespace-collapsed) - matches Android's `cacheUserMessage` heuristic so
    /// the sidebar's list reads the same way on both platforms.
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
