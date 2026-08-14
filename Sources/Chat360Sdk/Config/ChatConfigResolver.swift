import Foundation

@available(iOS 13.0, *)
private let defaultBaseUrl = "https://app.chat360.io"

@available(iOS 13.0, *)
public struct ResolvedChatConfig {
    public let botId: String
    public let baseUrl: String
    public let themePreset: Chat360ThemePreset
    public let customLightColors: Chat360Colors?
    public let customDarkColors: Chat360Colors?
    public let customTypography: Chat360Typography?
    public let customBranding: Chat360Branding?
    public let historyEnabled: Bool
    public let clientId: String?
    public let apiKey: String?
    public let endUserId: String?
    public let chat360UIConfig: Chat360UIConfig
}

@available(iOS 13.0, *)
public func resolveChatConfig() -> ResolvedChatConfig {
    let config = ConfigService.getInstance().getConfig()
    let configuredBotId = config.botId?.trimmingCharacters(in: .whitespacesAndNewlines)
    let botId = (configuredBotId?.isEmpty ?? true) ? "" : configuredBotId!

    return ResolvedChatConfig(
        botId: botId,
        baseUrl: ConfigService.getInstance().getBaseUrl().flatMap { $0.isBlank ? nil : $0 } ?? defaultBaseUrl,
        themePreset: config.themePreset,
        customLightColors: config.customLightColors,
        customDarkColors: config.customDarkColors,
        customTypography: config.customTypography,
        customBranding: config.customBranding,
        historyEnabled: config.historyEnabled,
        clientId: config.clientId.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.flatMap { $0.isEmpty ? nil : $0 },
        apiKey: config.apiKey.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.flatMap { $0.isEmpty ? nil : $0 },
        endUserId: config.endUserId.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.flatMap { $0.isEmpty ? nil : $0 },
        chat360UIConfig: config.chat360UIConfig ?? Chat360UIConfig()
    )
}
