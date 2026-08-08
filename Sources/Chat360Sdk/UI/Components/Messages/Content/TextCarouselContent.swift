import SwiftUI

/// Renders the TEXT_CAROUSEL node - both wire generations (`type1`/`type2`) render through this
/// one card shape.
struct TextCarouselContent: View {
    var message: ChatMessage
    var content: BotContent.TextCarousel
    var isLiveChat: Bool
    var onCardTap: (_ text: String, _ clickedIndex: Int, _ targetId: String?) -> Void

    private var enabled: Bool { message.repliesEnabled && !isLiveChat }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Array(content.cards.enumerated()), id: \.offset) { index, card in
                        TextCarouselCard(card: card, index: index, enabled: enabled, onCardTap: onCardTap)
                    }
                }
            }
            if !content.dynamicButtons.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(content.dynamicButtons.enumerated()), id: \.offset) { i, button in
                            QuickReplyButton(
                                text: button.title,
                                enabled: enabled,
                                selected: false,
                                onTap: { onCardTap(button.title, -(i + 1), button.componentUuid ?? button.targetId) }
                            )
                        }
                    }
                }
            }
        }
    }
}

private struct TextCarouselCard: View {
    var card: BotContent.TextCarousel.Card
    var index: Int
    var enabled: Bool
    var onCardTap: (String, Int, String?) -> Void

    @Environment(\.chat360Colors) private var colors
    @Environment(\.chat360Typography) private var typography
    @Environment(\.openURL) private var openURL

    private var backgroundColor: Color { card.bgColor?.toColorOrNull() ?? colors.cardBackground }

    var body: some View {
        content
            .padding(12)
            .frame(width: 220, alignment: .leading)
            .background(backgroundColor)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(colors.cardBorder, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .onTapGesture {
                guard enabled, let redirectLink = card.redirectLink else { return }
                if card.redirectType == "link", let url = URL(string: redirectLink) {
                    openURL(url)
                } else {
                    onCardTap(card.content ?? (card.name ?? ""), index, redirectLink)
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let bgImage = card.bgImage, !bgImage.isEmpty {
                AsyncImage(url: URL(string: bgImage)) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    colors.backgroundSunken
                }
                .frame(height: 137)
                .clipped()
            }
            if (card.iconText?.isEmpty == false) || (card.iconUrl?.isEmpty == false) {
                HStack(spacing: 6) {
                    if let iconUrl = card.iconUrl, !iconUrl.isEmpty {
                        AsyncImage(url: URL(string: iconUrl)) { image in
                            image.resizable().aspectRatio(contentMode: .fit)
                        } placeholder: { Color.clear }
                        .frame(width: 16, height: 16)
                    }
                    if let iconText = card.iconText {
                        Text(iconText).font(textFont(size: 12)).foregroundColor(colors.textSecondary)
                    }
                }
            }
            if let text = card.content {
                Text(text).font(textFont(size: 14)).fontWeight(.medium).foregroundColor(colors.textPrimary)
            }
            if let footer = card.footerText {
                Text(footer).font(textFont(size: 12)).foregroundColor(colors.textSecondary)
            }
            if card.ctaButtons.count == 2 {
                HStack(spacing: 8) {
                    ForEach(Array(card.ctaButtons.enumerated()), id: \.offset) { _, cta in
                        Button(action: {
                            if cta.type == "link", let url = URL(string: cta.link) {
                                openURL(url)
                            } else {
                                onCardTap(cta.name, index, cta.link)
                            }
                        }) {
                            Text(cta.name)
                                .font(textFont(size: 12))
                                .foregroundColor(colors.accentContrast)
                                .frame(width: 90)
                                .padding(.vertical, 8)
                                .background(enabled ? colors.accent : colors.textDisabled)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .disabled(!enabled)
                    }
                }
            }
            ForEach(Array(card.buttons.enumerated()), id: \.offset) { _, button in
                QuickReplyButton(text: button.label, enabled: enabled, selected: false, onTap: { onCardTap(button.label, index, button.link) })
            }
        }
    }

    private func textFont(size: CGFloat) -> Font {
        if let name = typography.textFontName { return .custom(name, size: size) }
        return .system(size: size)
    }
}
