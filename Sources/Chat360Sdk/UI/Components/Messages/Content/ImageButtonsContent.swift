import SwiftUI

@available(iOS 15.0, *)
public struct ImageButtonsContent: View {
    private let message: ChatMessage
    private let content: BotContent.ImageButtons
    private let isLiveChat: Bool
    private let onButtonClick: (BotContent.ImageButtons.Card, BotContent.ImageButtons.Button) -> Void

    public init(message: ChatMessage, content: BotContent.ImageButtons, isLiveChat: Bool, onButtonClick: @escaping (BotContent.ImageButtons.Card, BotContent.ImageButtons.Button) -> Void) {
        self.message = message
        self.content = content
        self.isLiveChat = isLiveChat
        self.onButtonClick = onButtonClick
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PlainTextContent(message.text)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Array(content.cards.enumerated()), id: \.offset) { _, card in
                        ImageButtonCard(card: card, enabled: message.repliesEnabled && !isLiveChat, onButtonClick: onButtonClick)
                    }
                }
            }
        }
    }
}

@available(iOS 15.0, *)
private struct ImageButtonCard: View {
    @Environment(\.chat360Colors) private var colors
    @Environment(\.chat360Typography) private var typography
    @Environment(\.openURL) private var openURL

    let card: BotContent.ImageButtons.Card
    let enabled: Bool
    let onButtonClick: (BotContent.ImageButtons.Card, BotContent.ImageButtons.Button) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            AsyncImage(url: URL(string: card.imageUrl)) { image in
                image.resizable().aspectRatio(1.4, contentMode: .fill)
            } placeholder: {
                Color.clear
            }
            .aspectRatio(1.4, contentMode: .fit)
            .clipped()

            VStack(alignment: .leading, spacing: 0) {
                if let description = card.description {
                    Text(description).font(typography.textFamily.font(size: 13)).foregroundColor(colors.textPrimary).lineLimit(2)
                }
                ForEach(Array(card.buttons.enumerated()), id: \.offset) { _, button in
                    Spacer().frame(height: 6)
                    Button(action: {
                        if button.type == "web_url", let url = button.url.flatMap({ URL(string: $0) }) {
                            openURL(url)
                        } else {
                            onButtonClick(card, button)
                        }
                    }) {
                        Text(button.text)
                            .font(typography.textFamily.font(size: 13))
                            .foregroundColor(colors.accentContrast)
                            .frame(width: 200)
                            .padding(.vertical, 10)
                            .background(enabled ? colors.accent : colors.textDisabled)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .disabled(!enabled)
                }
            }
            .padding(10)
        }
        .frame(width: 220)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(colors.cardBorder, lineWidth: 1))
    }
}
