import Foundation

/// Remembers which agent role each room was created for (`rooms/list`'s `agent_role`), so the history list
/// can badge a room before the next fetch, including while offline.
public protocol RoomRoleStore {
    /// Roles last returned by `rooms/list`.
    func load(botId: String) -> [String: String]
    func save(botId: String, roles: [String: String])

    /// Roles this device sent when it created a room - shown until `rooms/list` returns one for that room.
    func loadLocal(botId: String) -> [String: String]
    func saveLocal(botId: String, roles: [String: String])
}

public final class UserDefaultsRoomRoleStore: RoomRoleStore {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private func key(_ botId: String) -> String { "chat360_room_roles_\(botId)" }

    public func load(botId: String) -> [String: String] { read(key(botId)) }
    public func save(botId: String, roles: [String: String]) { defaults.set(roles, forKey: key(botId)) }
    public func loadLocal(botId: String) -> [String: String] { read(key(botId) + "_local") }
    public func saveLocal(botId: String, roles: [String: String]) { defaults.set(roles, forKey: key(botId) + "_local") }

    public func clear(botId: String) {
        defaults.removeObject(forKey: key(botId))
        defaults.removeObject(forKey: key(botId) + "_local")
    }

    private func read(_ key: String) -> [String: String] {
        defaults.dictionary(forKey: key) as? [String: String] ?? [:]
    }
}
