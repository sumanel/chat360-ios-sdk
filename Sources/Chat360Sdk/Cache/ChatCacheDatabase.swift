import Foundation
import SQLite3

public struct CachedConversationEntity: Equatable {
    public var id: String
    public var botId: String
    public var roomId: String?
    public var title: String = "New conversation"
    public var createdAt: Int64
    public var updatedAt: Int64

    public init(id: String, botId: String, roomId: String? = nil, title: String = "New conversation", createdAt: Int64, updatedAt: Int64) {
        self.id = id
        self.botId = botId
        self.roomId = roomId
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct CachedMessageEntity: Equatable {
    public var id: Int64 = 0
    public var conversationId: String
    public var kind: String
    public var payload: String
    public var chatMsgId: String?
    public var createdAt: Int64

    public init(id: Int64 = 0, conversationId: String, kind: String, payload: String, chatMsgId: String? = nil, createdAt: Int64) {
        self.id = id
        self.conversationId = conversationId
        self.kind = kind
        self.payload = payload
        self.chatMsgId = chatMsgId
        self.createdAt = createdAt
    }
}

public struct PendingFeedbackEntity: Equatable {
    public var messageId: String
    public var timestampMs: Int64?

    public init(messageId: String, timestampMs: Int64?) {
        self.messageId = messageId
        self.timestampMs = timestampMs
    }
}

@available(iOS 13.0, *)
public final class ChatCacheDao {
    private let db: OpaquePointer
    private let queue = DispatchQueue(label: "com.chat360.sdk.cache")
    private var conversationObservers: [String: [UUID: ([CachedConversationEntity]) -> Void]] = [:]

    init(db: OpaquePointer) {
        self.db = db
        createSchema()
    }

    private func createSchema() {
        queue.sync {
            exec("""
            CREATE TABLE IF NOT EXISTS chat_conversations (
                id TEXT PRIMARY KEY NOT NULL,
                botId TEXT NOT NULL,
                roomId TEXT,
                title TEXT NOT NULL DEFAULT 'New conversation',
                createdAt INTEGER NOT NULL,
                updatedAt INTEGER NOT NULL
            )
            """)
            exec("CREATE INDEX IF NOT EXISTS index_chat_conversations_botId_roomId ON chat_conversations(botId, roomId)")
            exec("""
            CREATE TABLE IF NOT EXISTS chat_messages (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                conversationId TEXT NOT NULL,
                kind TEXT NOT NULL,
                payload TEXT NOT NULL,
                chatMsgId TEXT,
                createdAt INTEGER NOT NULL,
                FOREIGN KEY(conversationId) REFERENCES chat_conversations(id) ON DELETE CASCADE
            )
            """)
            exec("CREATE INDEX IF NOT EXISTS index_chat_messages_conversationId ON chat_messages(conversationId)")
            exec("""
            CREATE TABLE IF NOT EXISTS chat_pending_feedback (
                messageId TEXT PRIMARY KEY NOT NULL,
                conversationId TEXT NOT NULL,
                createdAt INTEGER NOT NULL,
                timestampMs INTEGER,
                FOREIGN KEY(conversationId) REFERENCES chat_conversations(id) ON DELETE CASCADE
            )
            """)
            // Best-effort migration for installs that created this table before timestampMs
            // existed - fails harmlessly (ignored return value) if the column is already there.
            exec("ALTER TABLE chat_pending_feedback ADD COLUMN timestampMs INTEGER")
            exec("CREATE INDEX IF NOT EXISTS index_chat_pending_feedback_conversationId ON chat_pending_feedback(conversationId)")
            exec("""
            CREATE TABLE IF NOT EXISTS chat_message_reactions (
                conversationId TEXT NOT NULL,
                timestampMs INTEGER NOT NULL,
                liked INTEGER NOT NULL,
                PRIMARY KEY (conversationId, timestampMs)
            )
            """)
        }
    }

    @discardableResult
    private func exec(_ sql: String, params: [Any?] = []) -> Bool {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return false }
        defer { sqlite3_finalize(statement) }
        bind(statement, params)
        return sqlite3_step(statement) == SQLITE_DONE
    }

    private func query(_ sql: String, params: [Any?] = []) -> [[String: Any?]] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }
        bind(statement, params)
        var rows: [[String: Any?]] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            var row: [String: Any?] = [:]
            let columnCount = sqlite3_column_count(statement)
            for i in 0..<columnCount {
                let name = String(cString: sqlite3_column_name(statement, i))
                switch sqlite3_column_type(statement, i) {
                case SQLITE_INTEGER: row[name] = sqlite3_column_int64(statement, i)
                case SQLITE_TEXT: row[name] = String(cString: sqlite3_column_text(statement, i))
                case SQLITE_NULL: row[name] = nil
                default: row[name] = nil
                }
            }
            rows.append(row)
        }
        return rows
    }

    private func bind(_ statement: OpaquePointer?, _ params: [Any?]) {
        for (index, param) in params.enumerated() {
            let position = Int32(index + 1)
            switch param {
            case let value as String: sqlite3_bind_text(statement, position, value, -1, SQLITE_TRANSIENT)
            case let value as Int64: sqlite3_bind_int64(statement, position, value)
            case let value as Int: sqlite3_bind_int64(statement, position, Int64(value))
            case nil: sqlite3_bind_null(statement, position)
            default: sqlite3_bind_null(statement, position)
            }
        }
    }

    private func conversation(from row: [String: Any?]) -> CachedConversationEntity {
        CachedConversationEntity(
            id: row["id"] as? String ?? "",
            botId: row["botId"] as? String ?? "",
            roomId: row["roomId"] as? String,
            title: row["title"] as? String ?? "New conversation",
            createdAt: row["createdAt"] as? Int64 ?? 0,
            updatedAt: row["updatedAt"] as? Int64 ?? 0
        )
    }

    private func message(from row: [String: Any?]) -> CachedMessageEntity {
        CachedMessageEntity(
            id: row["id"] as? Int64 ?? 0,
            conversationId: row["conversationId"] as? String ?? "",
            kind: row["kind"] as? String ?? "",
            payload: row["payload"] as? String ?? "",
            chatMsgId: row["chatMsgId"] as? String,
            createdAt: row["createdAt"] as? Int64 ?? 0
        )
    }

    public func findConversation(botId: String, roomId: String) async -> CachedConversationEntity? {
        await withCheckedContinuation { continuation in
            queue.async {
                let rows = self.query(
                    "SELECT * FROM chat_conversations WHERE botId = ? AND roomId = ? LIMIT 1",
                    params: [botId, roomId]
                )
                continuation.resume(returning: rows.first.map { self.conversation(from: $0) })
            }
        }
    }

    public func observeConversations(botId: String) -> AsyncStream<[CachedConversationEntity]> {
        AsyncStream { continuation in
            let id = UUID()
            queue.async {
                self.conversationObservers[botId, default: [:]][id] = { conversations in
                    continuation.yield(conversations)
                }
                continuation.yield(self.conversationsSync(botId: botId))
            }
            continuation.onTermination = { [weak self] _ in
                self?.queue.async {
                    self?.conversationObservers[botId]?.removeValue(forKey: id)
                }
            }
        }
    }

    private func conversationsSync(botId: String) -> [CachedConversationEntity] {
        query("SELECT * FROM chat_conversations WHERE botId = ? ORDER BY updatedAt DESC", params: [botId])
            .map { conversation(from: $0) }
    }

    private func notifyConversationsChanged(botId: String) {
        let conversations = conversationsSync(botId: botId)
        conversationObservers[botId]?.values.forEach { $0(conversations) }
    }

    public func messages(conversationId: String) async -> [CachedMessageEntity] {
        await withCheckedContinuation { continuation in
            queue.async {
                let rows = self.query("SELECT * FROM chat_messages WHERE conversationId = ? ORDER BY id ASC", params: [conversationId])
                continuation.resume(returning: rows.map { self.message(from: $0) })
            }
        }
    }

    // A server room's `session_count` isn't a reliable "the user actually said something"
    // signal - it can already read 1 from the bot's own opening message, which is sent (and
    // cached) before any user reply. Local `chat_messages` rows of kind "USER" are only ever
    // written from a genuine user send (see `cacheUserMessage`), so that's the real signal.
    // Joined on roomId, not conversationId, since a room reconciled via `activateForRoom` keeps
    // its original local conversation id rather than the synced "agent-room:<roomId>" one.
    public func hasUserMessage(botId: String, roomId: String) async -> Bool {
        await withCheckedContinuation { continuation in
            queue.async {
                let rows = self.query(
                    """
                    SELECT 1 FROM chat_messages m
                    JOIN chat_conversations c ON m.conversationId = c.id
                    WHERE c.botId = ? AND c.roomId = ? AND m.kind = 'USER'
                    LIMIT 1
                    """,
                    params: [botId, roomId]
                )
                continuation.resume(returning: !rows.isEmpty)
            }
        }
    }

    private func agentRoomConversationIds(botId: String) -> [String] {
        query("SELECT id FROM chat_conversations WHERE botId = ? AND id LIKE 'agent-room:%'", params: [botId])
            .compactMap { $0["id"] as? String }
    }

    public func upsertConversation(_ conversation: CachedConversationEntity) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async {
                self.exec(
                    "INSERT OR REPLACE INTO chat_conversations (id, botId, roomId, title, createdAt, updatedAt) VALUES (?, ?, ?, ?, ?, ?)",
                    params: [conversation.id, conversation.botId, conversation.roomId, conversation.title, conversation.createdAt, conversation.updatedAt]
                )
                self.notifyConversationsChanged(botId: conversation.botId)
                continuation.resume()
            }
        }
    }

    public func insertConversationIfMissing(_ conversation: CachedConversationEntity) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async {
                self.exec(
                    "INSERT OR IGNORE INTO chat_conversations (id, botId, roomId, title, createdAt, updatedAt) VALUES (?, ?, ?, ?, ?, ?)",
                    params: [conversation.id, conversation.botId, conversation.roomId, conversation.title, conversation.createdAt, conversation.updatedAt]
                )
                self.notifyConversationsChanged(botId: conversation.botId)
                continuation.resume()
            }
        }
    }

    public func updateRemoteConversation(conversationId: String, roomId: String, title: String, updatedAt: Int64, botId: String) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async {
                self.exec(
                    "UPDATE chat_conversations SET roomId = ?, title = ?, updatedAt = ? WHERE id = ?",
                    params: [roomId, title, updatedAt, conversationId]
                )
                self.notifyConversationsChanged(botId: botId)
                continuation.resume()
            }
        }
    }

    public func replaceAgentRoomConversations(botId: String, conversations: [CachedConversationEntity]) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async {
                let refreshedIds = Set(conversations.map { $0.id })
                for id in self.agentRoomConversationIds(botId: botId) where !refreshedIds.contains(id) {
                    self.exec("DELETE FROM chat_conversations WHERE id = ?", params: [id])
                }
                for conversation in conversations {
                    self.exec(
                        "INSERT OR IGNORE INTO chat_conversations (id, botId, roomId, title, createdAt, updatedAt) VALUES (?, ?, ?, ?, ?, ?)",
                        params: [conversation.id, conversation.botId, conversation.roomId, conversation.title, conversation.createdAt, conversation.updatedAt]
                    )
                    self.exec(
                        "UPDATE chat_conversations SET roomId = ?, title = ?, updatedAt = ? WHERE id = ?",
                        params: [conversation.roomId ?? "", conversation.title, conversation.updatedAt, conversation.id]
                    )
                }
                self.notifyConversationsChanged(botId: botId)
                continuation.resume()
            }
        }
    }

    public func insertMessage(_ message: CachedMessageEntity) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async {
                self.exec(
                    "INSERT INTO chat_messages (conversationId, kind, payload, chatMsgId, createdAt) VALUES (?, ?, ?, ?, ?)",
                    params: [message.conversationId, message.kind, message.payload, message.chatMsgId, message.createdAt]
                )
                continuation.resume()
            }
        }
    }

    public func insertMessages(_ messages: [CachedMessageEntity]) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async {
                for message in messages {
                    self.exec(
                        "INSERT INTO chat_messages (conversationId, kind, payload, chatMsgId, createdAt) VALUES (?, ?, ?, ?, ?)",
                        params: [message.conversationId, message.kind, message.payload, message.chatMsgId, message.createdAt]
                    )
                }
                continuation.resume()
            }
        }
    }

    public func deleteMessages(conversationId: String) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async {
                self.exec("DELETE FROM chat_messages WHERE conversationId = ?", params: [conversationId])
                continuation.resume()
            }
        }
    }

    public func replaceMessages(conversationId: String, messages: [CachedMessageEntity]) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async {
                self.exec("DELETE FROM chat_messages WHERE conversationId = ?", params: [conversationId])
                for message in messages {
                    self.exec(
                        "INSERT INTO chat_messages (conversationId, kind, payload, chatMsgId, createdAt) VALUES (?, ?, ?, ?, ?)",
                        params: [message.conversationId, message.kind, message.payload, message.chatMsgId, message.createdAt]
                    )
                }
                continuation.resume()
            }
        }
    }

    public func insertPendingFeedbackIfMissing(messageId: String, conversationId: String, timestampMs: Int64?, createdAt: Int64) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async {
                self.exec(
                    "INSERT OR IGNORE INTO chat_pending_feedback (messageId, conversationId, createdAt, timestampMs) VALUES (?, ?, ?, ?)",
                    params: [messageId, conversationId, createdAt, timestampMs]
                )
                continuation.resume()
            }
        }
    }

    public func pendingFeedbackEntries(conversationId: String) async -> [PendingFeedbackEntity] {
        await withCheckedContinuation { continuation in
            queue.async {
                let rows = self.query(
                    "SELECT messageId, timestampMs FROM chat_pending_feedback WHERE conversationId = ? ORDER BY createdAt ASC",
                    params: [conversationId]
                )
                continuation.resume(returning: rows.compactMap { row in
                    guard let messageId = row["messageId"] as? String else { return nil }
                    return PendingFeedbackEntity(messageId: messageId, timestampMs: row["timestampMs"] as? Int64)
                })
            }
        }
    }

    public func deletePendingFeedback(messageId: String) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async {
                self.exec("DELETE FROM chat_pending_feedback WHERE messageId = ?", params: [messageId])
                continuation.resume()
            }
        }
    }

    public func setMessageReaction(conversationId: String, timestampMs: Int64, liked: Bool) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async {
                self.exec(
                    "INSERT OR REPLACE INTO chat_message_reactions (conversationId, timestampMs, liked) VALUES (?, ?, ?)",
                    params: [conversationId, timestampMs, liked ? 1 : 0]
                )
                continuation.resume()
            }
        }
    }

    public func deleteMessageReaction(conversationId: String, timestampMs: Int64) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async {
                self.exec(
                    "DELETE FROM chat_message_reactions WHERE conversationId = ? AND timestampMs = ?",
                    params: [conversationId, timestampMs]
                )
                continuation.resume()
            }
        }
    }

    public func messageReactions(conversationId: String) async -> [Int64: Bool] {
        await withCheckedContinuation { continuation in
            queue.async {
                let rows = self.query("SELECT timestampMs, liked FROM chat_message_reactions WHERE conversationId = ?", params: [conversationId])
                var result: [Int64: Bool] = [:]
                for row in rows {
                    guard let timestampMs = row["timestampMs"] as? Int64, let liked = row["liked"] as? Int64 else { continue }
                    result[timestampMs] = liked != 0
                }
                continuation.resume(returning: result)
            }
        }
    }

    public func setRoom(conversationId: String, roomId: String, updatedAt: Int64, botId: String) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async {
                self.exec("UPDATE chat_conversations SET roomId = ?, updatedAt = ? WHERE id = ?", params: [roomId, updatedAt, conversationId])
                self.notifyConversationsChanged(botId: botId)
                continuation.resume()
            }
        }
    }

    // Renaming is a metadata edit, not new activity - it must not bump updatedAt, or the
    // conversation would jump to the top of the (updatedAt-sorted) history list just from
    // being renamed, ahead of conversations the user actually did something in more recently.
    public func updateTitle(conversationId: String, title: String, botId: String) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async {
                self.exec("UPDATE chat_conversations SET title = ? WHERE id = ?", params: [title, conversationId])
                self.notifyConversationsChanged(botId: botId)
                continuation.resume()
            }
        }
    }

    public func touchAndSetTitleIfUnset(conversationId: String, title: String, updatedAt: Int64, botId: String) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async {
                self.exec(
                    "UPDATE chat_conversations SET title = CASE WHEN title = 'New conversation' THEN ? ELSE title END, updatedAt = ? WHERE id = ?",
                    params: [title, updatedAt, conversationId]
                )
                self.notifyConversationsChanged(botId: botId)
                continuation.resume()
            }
        }
    }

    public func deleteConversation(conversationId: String, botId: String) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async {
                self.exec("DELETE FROM chat_conversations WHERE id = ?", params: [conversationId])
                self.exec("DELETE FROM chat_messages WHERE conversationId = ?", params: [conversationId])
                self.exec("DELETE FROM chat_pending_feedback WHERE conversationId = ?", params: [conversationId])
                self.exec("DELETE FROM chat_message_reactions WHERE conversationId = ?", params: [conversationId])
                self.notifyConversationsChanged(botId: botId)
                continuation.resume()
            }
        }
    }

    public func touch(conversationId: String, updatedAt: Int64, botId: String) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async {
                self.exec("UPDATE chat_conversations SET updatedAt = ? WHERE id = ?", params: [updatedAt, conversationId])
                self.notifyConversationsChanged(botId: botId)
                continuation.resume()
            }
        }
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

@available(iOS 13.0, *)
public final class ChatCacheDatabase {
    public static let shared = ChatCacheDatabase()

    public let dao: ChatCacheDao
    private let connection: OpaquePointer

    private init() {
        var handle: OpaquePointer?
        sqlite3_open(ChatCacheDatabase.databaseURL().path, &handle)
        connection = handle!
        dao = ChatCacheDao(db: connection)
    }

    private static func databaseURL() -> URL {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("chat360_chat_cache.db")
    }
}
