import Foundation
import SQLite3

/// One cached conversation's metadata - the Swift analog of Android's Room
/// `CachedConversationEntity`. `id` is a client-generated UUID (the conversation's own identity),
/// distinct from `roomId` (the server-assigned room, nullable until the session establishing it
/// has actually run) - a conversation can exist locally before the server has assigned it a room.
public struct CachedConversation: Equatable, Identifiable {
    public var id: String
    public var botId: String
    public var roomId: String?
    public var title: String
    public var createdAt: Int64
    public var updatedAt: Int64
}

enum CachedMessageKind: String {
    /// A raw (unparsed) websocket envelope JSON string - replayed through the same
    /// `RawSocketEnvelope.toIncomingEvent()` pipeline as a live frame.
    case raw = "RAW"
    /// A locally-authored user message - plain display text, no wire shape to replay.
    case user = "USER"
}

struct CachedMessage {
    var id: Int64
    var conversationId: String
    var kind: CachedMessageKind
    var payload: String
    var chatMsgId: String?
    var createdAt: Int64
}

/// Thin SQLite3 wrapper mirroring Android's Room `ChatCacheDatabase`: a `chat_conversations`
/// metadata table joined to a `chat_messages` payload table (`ON DELETE CASCADE`), one file
/// shared by the whole process. All access happens on a private serial queue - SQLite connections
/// opened without the `SQLITE_OPEN_FULLMUTEX` flag (the default via `sqlite3_open`) aren't safe to
/// call concurrently from multiple threads.
final class ChatCacheDatabase {
    static let shared = ChatCacheDatabase()

    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "com.chat360.chatcache")

    private init() {
        queue.sync { openAndMigrate() }
    }

    private func openAndMigrate() {
        let path = Self.databasePath()
        guard sqlite3_open(path, &db) == SQLITE_OK else {
            print("[ChatCacheDatabase] failed to open at \(path): \(String(cString: sqlite3_errmsg(db)))")
            db = nil
            return
        }
        exec("PRAGMA foreign_keys = ON;")
        exec("""
        CREATE TABLE IF NOT EXISTS chat_conversations (
            id TEXT PRIMARY KEY NOT NULL,
            botId TEXT NOT NULL,
            roomId TEXT,
            title TEXT NOT NULL DEFAULT 'New conversation',
            createdAt INTEGER NOT NULL,
            updatedAt INTEGER NOT NULL
        );
        """)
        exec("CREATE INDEX IF NOT EXISTS idx_chat_conversations_bot_room ON chat_conversations(botId, roomId);")
        exec("""
        CREATE TABLE IF NOT EXISTS chat_messages (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            conversationId TEXT NOT NULL,
            kind TEXT NOT NULL,
            payload TEXT NOT NULL,
            chatMsgId TEXT,
            createdAt INTEGER NOT NULL,
            FOREIGN KEY(conversationId) REFERENCES chat_conversations(id) ON DELETE CASCADE
        );
        """)
        exec("CREATE INDEX IF NOT EXISTS idx_chat_messages_conversation ON chat_messages(conversationId);")
    }

    private static func databasePath() -> String {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("chat360_chat_cache.sqlite").path
    }

    @discardableResult
    fileprivate func exec(_ sql: String) -> Bool {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            print("[ChatCacheDatabase] exec failed: \(String(cString: sqlite3_errmsg(db))) -- \(sql)")
            return false
        }
        return true
    }

    /// Runs `body` synchronously on the serial DB queue. Deliberately blocking (not `async`) -
    /// SQLite reads/writes to a small local file are fast, and a synchronous API lets
    /// `cacheRaw`/`cacheUserMessage` be called durably from any thread (including a WebSocket
    /// callback thread) without racing a view's own lifetime, mirroring Android's deliberate
    /// `runBlocking` durability-over-cancellation choice for the same call site.
    @discardableResult
    func perform<T>(_ body: (OpaquePointer?) -> T) -> T {
        queue.sync { body(db) }
    }
}

// MARK: - Minimal prepared-statement helpers

/// Prepares `sql` and binds `?`-placeholders in order; `nil` binds SQL NULL.
func sqlitePrepare(_ db: OpaquePointer?, _ sql: String, _ params: [Any?] = []) -> OpaquePointer? {
    var stmt: OpaquePointer?
    guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
        print("[ChatCacheDatabase] prepare failed: \(String(cString: sqlite3_errmsg(db))) -- \(sql)")
        return nil
    }
    for (index, param) in params.enumerated() {
        let position = Int32(index + 1)
        switch param {
        case nil:
            sqlite3_bind_null(stmt, position)
        case let value as String:
            sqlite3_bind_text(stmt, position, value, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        case let value as Int64:
            sqlite3_bind_int64(stmt, position, value)
        case let value as Int:
            sqlite3_bind_int64(stmt, position, Int64(value))
        case let value as Bool:
            sqlite3_bind_int64(stmt, position, value ? 1 : 0)
        default:
            sqlite3_bind_null(stmt, position)
        }
    }
    return stmt
}

func sqliteColumnText(_ stmt: OpaquePointer?, _ index: Int32) -> String? {
    guard let cString = sqlite3_column_text(stmt, index) else { return nil }
    return String(cString: cString)
}
