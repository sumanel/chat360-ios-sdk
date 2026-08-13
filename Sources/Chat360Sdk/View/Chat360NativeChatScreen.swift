import SwiftUI

@available(iOS 16.0, *)
public struct Chat360NativeChatScreen: View {
    @StateObject private var viewModel: ChatViewModel
    private let uiConfig: Chat360UIConfig

    public init(botConfig: Chat360Config) {
        let resolvedBaseUrl = Chat360Bot.shared.getBaseUrl() ?? (botConfig.isDebug ? "https://staging.chat360.io" : "https://app.chat360.io")
        let resolvedBotId = botConfig.botId ?? ""

        let repository = ChatRepository(
            baseUrl: resolvedBaseUrl,
            botId: resolvedBotId,
            historyEnabled: true,
            sessionStore: UserDefaultsSessionStore()
        )
        let cache = ChatCacheRepository(dao: ChatCacheDatabase.shared.dao)
        _viewModel = StateObject(wrappedValue: ChatViewModel(repository: repository, botId: resolvedBotId, cache: cache))
        self.uiConfig = Chat360UIConfig()
    }

    public var body: some View {
        Chat360Theme(config: uiConfig) {
            ChatScreen(viewModel: viewModel)
        }
    }
}
