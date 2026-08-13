import Foundation

@available(iOS 13.0, *)
public final class CoreConfigs {
    public var botId: String?
    public var isDebug: Bool?
    public var flutter: Bool
    public var meta: [String: String]?
    public var useNewUI: Bool

    public var themePreset: Chat360ThemePreset = .default
    public var customLightColors: Chat360Colors?
    public var customDarkColors: Chat360Colors?
    public var customTypography: Chat360Typography?
    public var customBranding: Chat360Branding?
    public var historyEnabled: Bool = true

    public var clientId: String?
    public var apiKey: String?
    public var endUserId: String?
    public var chat360UIConfig: Chat360UIConfig?

    public init(botId: String, flutter: Bool, meta: [String: String]?, isDebug: Bool?, useNewUI: Bool) {
        self.botId = botId
        self.flutter = flutter
        self.meta = meta
        self.isDebug = isDebug
        self.useNewUI = useNewUI
    }
}
