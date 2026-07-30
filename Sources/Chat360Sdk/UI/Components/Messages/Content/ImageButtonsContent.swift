import SwiftUI

/// Ports the IMAGE_BUTTON node - a Carousel-shaped card per slide, each with its own buttons.
struct ImageButtonsContent: View {
    var message: ChatMessage
    var content: BotContent.ImageButtons
    var isLiveChat: Bool
    var onButtonClick: (BotContent.ImageButtons.Card, BotContent.ImageButtons.Button) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PlainTextContent(text: message.text)
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

private struct ImageButtonCard: View {
    var card: BotContent.ImageButtons.Card
    var enabled: Bool
    var onButtonClick: (BotContent.ImageButtons.Card, BotContent.ImageButtons.Button) -> Void

    @Environment(\.chat360Colors) private var colors
    @Environment(\.chat360Typography) private var typography
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            AsyncImage(url: URL(string: card.imageUrl)) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                colors.backgroundSunken
            }
            .frame(width: 220, height: 157)
            .clipped()

            VStack(alignment: .leading, spacing: 6) {
                if let description = card.description {
                    Text(description).font(textFont(size: 13)).foregroundColor(colors.textPrimary).lineLimit(2)
                }
                ForEach(Array(card.buttons.enumerated()), id: \.offset) { _, button in
                    Button(action: {
                        if button.type == "web_url", let urlString = button.url, let url = URL(string: urlString) {
                            openURL(url)
                        } else {
                            onButtonClick(card, button)
                        }
                    }) {
                        Text(button.text)
                            .font(textFont(size: 13))
                            .foregroundColor(colors.accentContrast)
                            .frame(width: 200)
                            .padding(.vertical, 10)
                            .background(enabled ? colors.accent : colors.textDisabled)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .disabled(!enabled)
                }
            }
            .padding(10)
        }
        .frame(width: 220)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(colors.cardBorder, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func textFont(size: CGFloat) -> Font {
        if let name = typography.textFontName { return .custom(name, size: size) }
        return .system(size: size)
    }
}
