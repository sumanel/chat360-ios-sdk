import SwiftUI

@available(iOS 15.0, *)
public struct WelcomeScreenContent: View {
    @Environment(\.chat360Colors) private var colors
    @Environment(\.chat360Typography) private var typography
    @Environment(\.openURL) private var openURL

    private let message: ChatMessage
    private let content: BotContent.WelcomeScreen
    private let isLiveChat: Bool
    private let onCardSelected: (BotContent.WelcomeScreen.Card, Int) -> Void

    public init(message: ChatMessage, content: BotContent.WelcomeScreen, isLiveChat: Bool, onCardSelected: @escaping (BotContent.WelcomeScreen.Card, Int) -> Void) {
        self.message = message
        self.content = content
        self.isLiveChat = isLiveChat
        self.onCardSelected = onCardSelected
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let iconUrl = content.iconUrl, !iconUrl.isBlank {
                AsyncImage(url: URL(string: iconUrl)) { image in
                    image.resizable().aspectRatio(contentMode: .fit)
                } placeholder: {
                    Color.clear
                }
                .frame(width: 40, height: 40)
                Spacer().frame(height: 8)
            } else {
                LogoBadge(size: 40)
                Spacer().frame(height: 8)
            }
            if let title = content.title {
                Text(title).font(typography.headFamily.font(size: 18, weight: .semibold)).foregroundColor(colors.textPrimary)
                Spacer().frame(height: 4)
            }
            if let description = content.description {
                Text(description).font(typography.textFamily.font(size: 13)).foregroundColor(colors.textSecondary)
            }
            if !content.cards.isEmpty {
                Spacer().frame(height: 10)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(Array(content.cards.enumerated()), id: \.offset) { index, card in
                            WelcomeCard(
                                card: card,
                                enabled: message.repliesEnabled && !isLiveChat,
                                onTap: {
                                    if card.ctaEnabled, card.ctaType == "external_link", let link = card.ctaLink, !link.isBlank, let url = URL(string: link) {
                                        openURL(url)
                                    }
                                    onCardSelected(card, index)
                                }
                            )
                        }
                    }
                }
            }
        }
    }
}

@available(iOS 15.0, *)
private struct WelcomeCard: View {
    @Environment(\.chat360Colors) private var colors
    @Environment(\.chat360Typography) private var typography
    let card: BotContent.WelcomeScreen.Card
    let enabled: Bool
    let onTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title = card.title {
                Text(title).font(typography.textFamily.font(size: 13, weight: .medium)).foregroundColor(colors.textPrimary)
            }
        }
        .padding(12)
        .frame(width: 160, alignment: .topLeading)
        .background(card.bgColor?.toChat360Color() ?? colors.cardBackground)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(colors.cardBorder, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .contentShape(Rectangle())
        .onTapGesture { if enabled { onTap() } }
    }
}
