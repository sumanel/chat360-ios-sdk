import SwiftUI

/// Hosts the native `ChatScreen` (the `rewrite/native-kotlin`-equivalent port) behind the same
/// `ChatController` the SDK's public API has always presented - replacing the WebView content
/// entirely, mirroring how the Android SDK's `Chat360.startBot()` now always launches
/// `ChatComposeActivity` instead of the old WebView Activity.
///
/// Just a thin `.id()`-keyed wrapper around `Chat360ChatSession` - see that type for why "new
/// session" recreates the whole subtree instead of resetting one `ChatViewModel` in place.
@available(iOS 15.0, *)
struct Chat360NativeChatScreen: View {
    let botConfig: Chat360Config
    @State private var sessionId = UUID()

    init(botConfig: Chat360Config) {
        self.botConfig = botConfig
    }

    var body: some View {
        Chat360ChatSession(botConfig: botConfig, onNewSession: { sessionId = UUID() })
            .id(sessionId)
    }
}

/// Owns the `ChatViewModel`/connection for exactly one chat session. `onNewSession` (wired to the
/// header's "+" button) doesn't reset this instance - it changes the parent's `.id()`, which tears
/// this whole view down (running `.onDisappear` -> `viewModel.disconnect()`) and rebuilds a fresh
/// one with a brand-new `ChatViewModel`/`ChatRepository`. Reusing one `ChatRepository` across
/// sessions instead would be wrong: `disconnect()` latches `manuallyDisconnected = true`
/// permanently, so a second `connect()` on the same instance would silently never auto-reconnect.
@available(iOS 15.0, *)
private struct Chat360ChatSession: View {
    @StateObject private var viewModel: ChatViewModel
    let botConfig: Chat360Config
    let onNewSession: () -> Void

    init(botConfig: Chat360Config, onNewSession: @escaping () -> Void) {
        self.botConfig = botConfig
        self.onNewSession = onNewSession
        _viewModel = StateObject(wrappedValue: ChatViewModel(
            baseUrl: botConfig.resolvedBaseUrl,
            botId: botConfig.botId ?? "",
            historyEnabled: botConfig.historyEnabled
        ))
    }

    var body: some View {
        NavigationView {
            ChatScreen(viewModel: viewModel, onNewSession: onNewSession)
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
            customBranding: botConfig.customBranding
        )
        .onDisappear { viewModel.disconnect() }
    }
}
