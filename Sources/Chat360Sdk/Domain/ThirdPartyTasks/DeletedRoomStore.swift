import Foundation

/// Remembers which rooms the user deleted from the history list on this device.
///
/// Deleting only asks the server to mark the room inactive, and `rooms/list` keeps returning inactive rooms - so
/// without this record a deleted room came straight back the next time the list was refreshed (opening the
/// drawer). Anything recorded here is filtered out of every `rooms/list` page.
public protocol DeletedRoomStore {
    func load(botId: String) -> Set<String>
    func add(botId: String, roomId: String)
}

public final class UserDefaultsDeletedRoomStore: DeletedRoomStore {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private func key(_ botId: String) -> String { "chat360_deleted_rooms_\(botId)" }

    public func load(botId: String) -> Set<String> {
        Set(defaults.stringArray(forKey: key(botId)) ?? [])
    }

    public func add(botId: String, roomId: String) {
        defaults.set(Array(load(botId: botId).union([roomId])), forKey: key(botId))
    }

    public func clear(botId: String) {
        defaults.removeObject(forKey: key(botId))
    }
}
