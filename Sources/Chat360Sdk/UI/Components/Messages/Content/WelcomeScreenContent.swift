import SwiftUI

/// Ports the WELCOME_SCREEN node's card content + `onCardClick` exactly (see
/// `BotContent.WelcomeScreen`'s doc); the "pinned outside the scroll list" placement for whichever
/// WELCOME_SCREEN message is currently the latest is handled by the caller (`ChatScreen`), not here.
struct WelcomeScreenContent: View {
    var message: ChatMessage
    var content: BotContent.WelcomeScreen
    var isLiveChat: Bool
    var onCardSelected: (BotContent.WelcomeScreen.Card, Int) -> Void

    @Environment(\.chat360Colors) private var colors
    @Environment(\.chat360Typography) private var typography
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let iconUrl = content.iconUrl, !iconUrl.isEmpty {
                AsyncImage(url: URL(string: iconUrl)) { image in
                    image.resizable().aspectRatio(contentMode: .fit)
                } placeholder: { Color.clear }
                .frame(width: 40, height: 40)
            } else {
                LogoBadge(size: 40)
            }
            if let title = content.title {
                Text(title).font(headFont(size: 18)).fontWeight(.semibold).foregroundColor(colors.textPrimary)
            }
            if let description = content.description {
                Text(description).font(textFont(size: 13)).foregroundColor(colors.textSecondary)
            }
            if !content.cards.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(Array(content.cards.enumerated()), id: \.offset) { index, card in
                            welcomeCard(card, index: index)
                        }
                    }
                }
            }
        }
    }

    private func welcomeCard(_ card: BotContent.WelcomeScreen.Card, index: Int) -> some View {
        let enabled = message.repliesEnabled && !isLiveChat
        return VStack(alignment: .leading, spacing: 0) {
            if let title = card.title {
                Text(title).font(textFont(size: 13)).fontWeight(.medium).foregroundColor(colors.textPrimary)
            }
        }
        .padding(12)
        .frame(width: 160, alignment: .leading)
        .background(card.bgColor?.toColorOrNull() ?? colors.cardBackground)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(colors.cardBorder, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .onTapGesture {
            guard enabled else { return }
            // external_link cards open externally AND still submit a reply.
            if card.ctaEnabled, card.ctaType == "external_link", let link = card.ctaLink, !link.isEmpty, let url = URL(string: link) {
                openURL(url)
            }
            onCardSelected(card, index)
        }
    }

    private func headFont(size: CGFloat) -> Font {
        if let name = typography.headFontName { return .custom(name, size: size) }
        return .system(size: size)
    }

    private func textFont(size: CGFloat) -> Font {
        if let name = typography.textFontName { return .custom(name, size: size) }
        return .system(size: size)
    }
}
