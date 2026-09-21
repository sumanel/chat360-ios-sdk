import Foundation

/// The local cache, the saved session and the room roles are all kept per bot, not per user - so when a
/// different user (`endUserId`) opens the same bot on this device they would otherwise see the previous
/// user's conversations in the history menu and resume their room. This remembers which user each bot's
/// local data belongs to and wipes it when that changes.
public final class ChatIdentityGuard {
    private let defaults: UserDefaults
    private let sessionStore: UserDefaultsSessionStore
    private let roleStore: UserDefaultsRoomRoleStore
    private let clearCache: (String) -> Void

    public init(
        defaults: UserDefaults = UserDefaults(suiteName: "chat360_identity") ?? .standard,
        sessionStore: UserDefaultsSessionStore = UserDefaultsSessionStore(),
        roleStore: UserDefaultsRoomRoleStore = UserDefaultsRoomRoleStore(),
        clearCache: @escaping (String) -> Void
    ) {
        self.defaults = defaults
        self.sessionStore = sessionStore
        self.roleStore = roleStore
        self.clearCache = clearCache
    }

    /// Call before the chat screen reads any local data. Returns true if it cleared something.
    @discardableResult
    public func apply(botId: String, endUserId: String?) -> Bool {
        guard !botId.isEmpty else { return false }
        let current = endUserId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let stored = defaults.string(forKey: key(botId))
        if stored == current { return false }
        defaults.set(current, forKey: key(botId))
        // Never recorded and no user now: there is nothing to tell apart, so keep what is there.
        if stored == nil && current.isEmpty { return false }
        wipe(botId: botId)
        return true
    }

    /// For a host's logout: forgets the local conversations, session and roles of [botId] outright.
    public func reset(botId: String) {
        defaults.removeObject(forKey: key(botId))
        wipe(botId: botId)
    }

    private func wipe(botId: String) {
        clearCache(botId)
        sessionStore.clear(botId: botId)
        roleStore.clear(botId: botId)
    }

    private func key(_ botId: String) -> String { "\(botId).endUserId" }
}
