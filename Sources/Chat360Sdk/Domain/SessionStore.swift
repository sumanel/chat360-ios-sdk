import Foundation

public struct PersistedSession: Equatable {
    public let roomId: String
    public let sessionToken: String?
    public let ownerId: String

    public init(roomId: String, sessionToken: String?, ownerId: String) {
        self.roomId = roomId
        self.sessionToken = sessionToken
        self.ownerId = ownerId
    }
}

public protocol SessionStore {
    func load(botId: String) -> PersistedSession?
    func loadForRoom(botId: String, roomId: String) -> PersistedSession?
    func save(botId: String, session: PersistedSession)
}

public final class UserDefaultsSessionStore: SessionStore {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = UserDefaults(suiteName: "chat360_session_store") ?? .standard) {
        self.defaults = defaults
    }

    public func load(botId: String) -> PersistedSession? {
        read(prefix: lastKeyPrefix(botId))
    }

    public func loadForRoom(botId: String, roomId: String) -> PersistedSession? {
        read(prefix: roomKeyPrefix(botId, roomId))
    }

    public func save(botId: String, session: PersistedSession) {
        write(prefix: lastKeyPrefix(botId), session: session)
        write(prefix: roomKeyPrefix(botId, session.roomId), session: session)
    }

    private func read(prefix: String) -> PersistedSession? {
        guard let roomId = defaults.string(forKey: "\(prefix).roomId") else { return nil }
        guard let ownerId = defaults.string(forKey: "\(prefix).ownerId") else { return nil }
        let sessionToken = defaults.string(forKey: "\(prefix).sessionToken")
        return PersistedSession(roomId: roomId, sessionToken: sessionToken, ownerId: ownerId)
    }

    private func write(prefix: String, session: PersistedSession) {
        defaults.set(session.roomId, forKey: "\(prefix).roomId")
        defaults.set(session.sessionToken, forKey: "\(prefix).sessionToken")
        defaults.set(session.ownerId, forKey: "\(prefix).ownerId")
    }

    private func lastKeyPrefix(_ botId: String) -> String { "\(botId).last" }
    private func roomKeyPrefix(_ botId: String, _ roomId: String) -> String { "\(botId).room.\(roomId)" }
}
