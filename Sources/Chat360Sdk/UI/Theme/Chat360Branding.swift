import Foundation

/// Where the bot's avatar/logo image comes from. A brand with no logo at all (the generic
/// default) is `nil` on `Chat360Branding.logo` - `LogoBadge` falls back to a plain
/// initial-letter badge in that case, never a broken image.
public enum Chat360Logo: Equatable {
    /// A bundled asset-catalog image name, optionally with a separate dark-theme variant.
    case resource(light: String, dark: String? = nil)
    /// A remote image (e.g. a client's own logo returned by the bot appearance API).
    case remote(url: String)
}

public struct Chat360Branding: Equatable {
    public var botTitle: String
    public var logo: Chat360Logo?
    public var welcomeHeading: String
    public var disclaimerText: String
    public var inputPlaceholder: String

    public init(
        botTitle: String,
        logo: Chat360Logo?,
        welcomeHeading: String? = nil,
        disclaimerText: String? = nil,
        inputPlaceholder: String = "Type a message…"
    ) {
        self.botTitle = botTitle
        self.logo = logo
        self.welcomeHeading = welcomeHeading ?? botTitle
        self.disclaimerText = disclaimerText ?? "\(botTitle) can make mistakes. Verify important information."
        self.inputPlaceholder = inputPlaceholder
    }
}

/// The library's own brand-neutral default: no logo image, a generic assistant title.
public let DefaultBranding = Chat360Branding(botTitle: "Chat360 Assistant", logo: nil)
