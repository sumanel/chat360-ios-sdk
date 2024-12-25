import SwiftUI

@available(iOS 13.0, *)
struct Chat360BotScreen: View {
    let botConfig: Chat360Config

    init(botConfig: Chat360Config) {
        self.botConfig = botConfig
    }

    var body: some View {
        NavigationView {
            VStack {
                if #available(iOS 16.0, *) {
                    ScrollView {
                        Chat360BotView(botConfig: botConfig)
                            .frame(height: UIScreen.main.bounds.size.height - 100)
                    }
                    .scrollDisabled(true)
                } else {
                    // Fallback on earlier versions
                    ScrollView {
                        Chat360BotView(botConfig: botConfig)
                            .frame(height: UIScreen.main.bounds.size.height - 100)
                    }
                    .disabled(true)
                }
            }
            .navigationBarItems(leading: Button(action: {
                try? Chat360Bot.shared.closeChatBot();
            }) {
                Image(systemName: "arrow.left")
                    .foregroundColor(.black) 
            })
        }
    }

}

