import SwiftUI

@available(iOS 16.0, *)
public struct Chat360NativeChatScreen: View {
    @StateObject private var viewModel: ChatViewModel
    private let botConfig: Chat360Config

    public init(botConfig: Chat360Config) {
        self.botConfig = botConfig
        let resolvedBaseUrl = Chat360Bot.shared.getBaseUrl() ?? (botConfig.isDebug ? "https://staging.chat360.io" : "https://app.chat360.io")
        let resolvedBotId = botConfig.botId ?? ""

        let repository = ChatRepository(
            baseUrl: resolvedBaseUrl,
            botId: resolvedBotId,
            historyEnabled: botConfig.historyEnabled,
            sessionStore: UserDefaultsSessionStore()
        )
        let cache = ChatCacheRepository(dao: ChatCacheDatabase.shared.dao)
        let historyRepository = Chat360NativeChatScreen.buildChatHistoryRepository(botConfig: botConfig, baseUrl: resolvedBaseUrl, botId: resolvedBotId, cache: cache)
        _viewModel = StateObject(wrappedValue: ChatViewModel(
            repository: repository,
            botId: resolvedBotId,
            cache: cache,
            chatHistoryRepository: historyRepository,
            suppressInitialBotMessages: botConfig.uiConfig?.behavior.suppressInitialBotMessages ?? false
        ))
    }

    private static func buildChatHistoryRepository(botConfig: Chat360Config, baseUrl: String, botId: String, cache: ChatCacheRepository) -> ChatHistoryRepository? {
        let trimmedClientId = botConfig.clientId.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.flatMap { $0.isEmpty ? nil : $0 }
        let trimmedApiKey = botConfig.apiKey.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.flatMap { $0.isEmpty ? nil : $0 }
        let trimmedEndUserId = botConfig.endUserId.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.flatMap { $0.isEmpty ? nil : $0 }
        guard let clientId = trimmedClientId, let apiKey = trimmedApiKey, let endUserId = trimmedEndUserId, !botId.isEmpty else {
            return nil
        }
        let thirdPartyApi = ThirdPartyTasksApiService(baseUrl: baseUrl)
        let tokenManager = ThirdPartyTokenManager(apiService: thirdPartyApi, clientId: clientId, apiKey: apiKey)
        return ChatHistoryRepository(apiService: thirdPartyApi, tokenManager: tokenManager, cache: cache, clientId: clientId, botId: botId, endUserId: endUserId)
    }

    public var body: some View {
        Chat360Theme(
            preset: botConfig.themePreset,
            customLightColors: botConfig.customLightColors,
            customDarkColors: botConfig.customDarkColors,
            customTypography: botConfig.customTypography,
            customBranding: botConfig.customBranding,
            config: botConfig.uiConfig ?? Chat360UIConfig()
        ) {
            let features = botConfig.uiConfig?.features ?? Chat360FeatureConfig()
            let hasHeaderBar = features.showMenu || features.showNewChat
            ZStack(alignment: .topTrailing) {
                ChatScreen(viewModel: viewModel)
                CloseChatButton()
                    .padding(.top, hasHeaderBar ? 66 : 8)
            }
        }
    }
}

@available(iOS 16.0, *)
private struct CloseChatButton: View {
    @Environment(\.chat360Colors) private var colors

    var body: some View {
        Button(action: { Chat360Bot.shared.closeChatBot() }) {
            Image(systemName: "xmark")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(colors.textPrimary)
                .frame(width: 32, height: 32)
                .background(colors.backgroundElevated)
                .clipShape(Circle())
                .overlay(Circle().stroke(colors.line, lineWidth: 1))
        }
        .padding(.trailing, 16)
    }
}
