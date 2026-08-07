import SwiftUI

/// Hosts the native `ChatScreen` (the `rewrite/native-kotlin`-equivalent port) behind the same
/// `ChatController` the SDK's public API has always presented - replacing the WebView content
/// entirely, mirroring how the Android SDK's `Chat360.startBot()` now always launches
/// `ChatComposeActivity` instead of the old WebView Activity.
@available(iOS 15.0, *)
struct Chat360NativeChatScreen: View {
    let botConfig: Chat360Config

    init(botConfig: Chat360Config) {
        self.botConfig = botConfig
    }

    var body: some View {
        Chat360ChatSession(botConfig: botConfig)
    }
}

/// Owns the `ChatViewModel`/connection for the lifetime of the chat screen. "New chat" (the
/// header's "+" button / the drawer's New Chat button) no longer tears this view down - it calls
/// `ChatViewModel.startNewChat()`, which creates a new locally-cached conversation and re-runs
/// session-init on the existing `ChatRepository` (`ChatRepository.startNewSession()`) so the
/// backend allocates a genuinely new room, while `conversations`/`shortcuts`/`languages` state
/// (and the local cache DB connection) stays put across the switch.
@available(iOS 15.0, *)
private struct Chat360ChatSession: View {
    @StateObject private var viewModel: ChatViewModel
    let botConfig: Chat360Config
    /// `nil` means "follow the system setting" - lives here (not in `ChatDrawer`) so it survives
    /// the drawer closing/reopening across the lifetime of one session.
    @State private var appearanceOverride: ColorScheme?

    init(botConfig: Chat360Config) {
        self.botConfig = botConfig
        _viewModel = StateObject(wrappedValue: ChatViewModel(
            baseUrl: botConfig.resolvedBaseUrl,
            botId: botConfig.botId ?? "",
            historyEnabled: botConfig.historyEnabled,
            conversationStarterEnabled: botConfig.conversationStarterEnabled
        ))
    }

    var body: some View {
        NavigationView {
            ChatScreen(viewModel: viewModel, appearanceOverride: $appearanceOverride)
                .navigationBarTitleDisplayMode(.inline)
                .navigationBarItems(leading: Button(action: {
                    try? Chat360Bot.shared.closeChatBot()
                }) {
                    Image(systemName: "chevron.left")
                        .foregroundColor(.primary)
                })
        }
        .navigationViewStyle(.stack)
        .chat360Theme(
            preset: botConfig.themePreset,
            customLightColors: botConfig.customLightColors,
            customDarkColors: botConfig.customDarkColors,
            customTypography: botConfig.customTypography,
            customBranding: botConfig.customBranding,
            inputBarConfig: botConfig.inputBarConfig,
            colorSchemeOverride: appearanceOverride
        )
        .preferredColorScheme(appearanceOverride)
        .onDisappear { viewModel.disconnect() }
    }
}
