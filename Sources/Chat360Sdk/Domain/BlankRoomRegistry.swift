import Foundation

/// The room, per bot, that the server created but no user message has been sent in yet.
///
/// Process-lifetime only (deliberately never persisted): reopening the chat screen while the host
/// app is still running goes back to this room instead of allocating another empty one, while a
/// genuine app restart starts empty and so gets a brand-new room, as intended.
enum BlankRoomRegistry {
    private static let lock = NSLock()
    private static var rooms: [String: String] = [:]

    static func roomId(botId: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        return rooms[botId]
    }

    static func set(botId: String, roomId: String) {
        lock.lock(); defer { lock.unlock() }
        rooms[botId] = roomId
    }

    /// Only clears when [roomId] is still the registered one - a different room turning non-blank
    /// says nothing about the blank one.
    static func clear(botId: String, roomId: String?) {
        lock.lock(); defer { lock.unlock() }
        if roomId == nil || rooms[botId] == roomId { rooms[botId] = nil }
    }
}
