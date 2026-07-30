import SwiftUI

/// Hosts the native `ChatScreen` (the `rewrite/native-kotlin`-equivalent port) behind the same
/// `ChatController` the SDK's public API has always presented - replacing the WebView content
/// entirely, mirroring how the Android SDK's `Chat360.startBot()` now always launches
/// `ChatComposeActivity` instead of the old WebView Activity.
@available(iOS 15.0, *)
struct Chat360NativeChatScreen: View {
    @StateObject private var viewModel: ChatViewModel
    let botConfig: Chat360Config

    init(botConfig: Chat360Config) {
        self.botConfig = botConfig
        _viewModel = StateObject(wrappedValue: ChatViewModel(
            baseUrl: botConfig.resolvedBaseUrl,
            botId: botConfig.botId ?? "",
            historyEnabled: botConfig.historyEnabled
        ))
    }

    var body: some View {
        NavigationView {
            ChatScreen(viewModel: viewModel)
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
