import SwiftUI

@available(iOS 13.0, *)
struct Chat360BotScreen: View {
    let botConfig: Chat360Config

    init(botConfig: Chat360Config) {
        self.botConfig = botConfig
    }

    var body: some View {
        NavigationView {
            Chat360BotView(botConfig: botConfig)
                .navigationBarItems(leading: Button(action: {
                    try? Chat360Bot.shared.closeChatBot();
                }) {
                    Image(systemName: "arrow.left")
                        .foregroundColor(.black)
                })
        }
    }

}

