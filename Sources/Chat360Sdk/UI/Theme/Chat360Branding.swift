import SwiftUI

@available(iOS 13.0, *)
public enum Chat360Logo: Equatable {
    case resource(light: String, dark: String)
    case remote(url: String)

    public static func resource(_ name: String) -> Chat360Logo {
        .resource(light: name, dark: name)
    }
}

@available(iOS 13.0, *)
public struct Chat360Branding: Equatable {
    public var botTitle: String
    public var logo: Chat360Logo?
    public var welcomeHeading: String
    public var disclaimerText: String
    public var inputPlaceholder: String
    public var welcomeLogoSize: CGFloat?

    public init(
        botTitle: String,
        logo: Chat360Logo?,
        welcomeHeading: String? = nil,
        disclaimerText: String? = nil,
        inputPlaceholder: String = "Type a message…",
        welcomeLogoSize: CGFloat? = nil
    ) {
        self.botTitle = botTitle
        self.logo = logo
        self.welcomeHeading = welcomeHeading ?? botTitle
        self.disclaimerText = disclaimerText ?? "\(botTitle) can make mistakes. Verify important information."
        self.inputPlaceholder = inputPlaceholder
        self.welcomeLogoSize = welcomeLogoSize
    }
}

@available(iOS 13.0, *)
public let defaultBranding = Chat360Branding(botTitle: "Chat360 Assistant", logo: nil)

@available(iOS 13.0, *)
public struct Chat360BrandingKey: EnvironmentKey {
    public static let defaultValue: Chat360Branding = defaultBranding
}

@available(iOS 13.0, *)
extension EnvironmentValues {
    public var chat360Branding: Chat360Branding {
        get { self[Chat360BrandingKey.self] }
        set { self[Chat360BrandingKey.self] = newValue }
    }
}

@available(iOS 13.0, *)
extension Chat360Branding {
    /// Puts the server-configured welcome copy over this branding's welcome heading and subtitle. The order
    /// is server value, then whatever this branding already resolved to (the host app's `welcomeTitle` /
    /// `welcomeSubtitle`, then the theme default). A missing or blank server field leaves that line alone.
    public func withWelcome(_ welcome: WelcomeText?) -> Chat360Branding {
        var result = self
        if let heading = welcome?.heading, !heading.isBlank { result.welcomeHeading = heading }
        if let text = welcome?.text, !text.isBlank { result.disclaimerText = text }
        return result
    }
}
