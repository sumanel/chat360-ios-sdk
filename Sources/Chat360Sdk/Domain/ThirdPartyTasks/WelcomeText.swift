import Foundation

/// The welcome screen copy configured for a client on the server (`third-party-tasks/welcome-text`).
/// Either field can be nil: a blank one means "nothing configured", not "show an empty heading".
public struct WelcomeText: Equatable {
    public let heading: String?
    public let text: String?

    public init(heading: String?, text: String?) {
        self.heading = heading
        self.text = text
    }

    public var isEmpty: Bool { heading == nil && text == nil }
}

/// Where the last good `WelcomeText` is kept between launches, so the welcome screen shows it instantly.
public protocol WelcomeTextStore {
    func load(clientId: String) -> WelcomeText?
    func save(clientId: String, welcomeText: WelcomeText?)
}

public final class UserDefaultsWelcomeTextStore: WelcomeTextStore {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = UserDefaults(suiteName: "chat360_welcome_text") ?? .standard) {
        self.defaults = defaults
    }

    public func load(clientId: String) -> WelcomeText? {
        let value = WelcomeText(heading: defaults.string(forKey: "\(clientId).heading"), text: defaults.string(forKey: "\(clientId).text"))
        return value.isEmpty ? nil : value
    }

    public func save(clientId: String, welcomeText: WelcomeText?) {
        defaults.set(welcomeText?.heading, forKey: "\(clientId).heading")
        defaults.set(welcomeText?.text, forKey: "\(clientId).text")
    }
}

/// Best-effort source of the server-configured welcome copy. Never throws to the caller and never affects
/// the chat itself: when nothing usable comes back, the welcome screen simply keeps the text the host app
/// supplied (or the theme's default).
@available(iOS 13.0, *)
public final class WelcomeTextRepository {
    private let apiService: ThirdPartyTasksApiService
    private let clientId: String
    private let store: WelcomeTextStore

    public init(apiService: ThirdPartyTasksApiService, clientId: String, store: WelcomeTextStore) {
        self.apiService = apiService
        self.clientId = clientId
        self.store = store
    }

    /// The last good response, for an instant first paint.
    public func cached() -> WelcomeText? { store.load(clientId: clientId) }

    /// Asks the server. Returns `.success` with the fresh copy (nil when the server has none configured) and
    /// updates the cache to match; returns `.failure` for anything else - offline, 404 while the endpoint
    /// isn't deployed, a malformed reply - in which case the cache is deliberately left alone, so a flaky
    /// connection never wipes a welcome that was working.
    public func refresh() async -> Result<WelcomeText?, Error> {
        do {
            let fresh = try await apiService.fetchWelcomeText(clientId: clientId)
            store.save(clientId: clientId, welcomeText: fresh)
            return .success(fresh)
        } catch {
            NSLog("[Chat360] third-party-tasks welcome-text unavailable: %@", error.localizedDescription)
            return .failure(error)
        }
    }
}
