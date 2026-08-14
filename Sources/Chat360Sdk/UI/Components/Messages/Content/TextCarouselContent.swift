import SwiftUI

@available(iOS 16.0, *)
public struct TextCarouselContent: View {
    private let message: ChatMessage
    private let content: BotContent.TextCarousel
    private let isLiveChat: Bool
    private let onCardTap: (String, Int, String?) -> Void

    public init(message: ChatMessage, content: BotContent.TextCarousel, isLiveChat: Bool, onCardTap: @escaping (String, Int, String?) -> Void) {
        self.message = message
        self.content = content
        self.isLiveChat = isLiveChat
        self.onCardTap = onCardTap
    }

    private var enabled: Bool { message.repliesEnabled && !isLiveChat }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Array(content.cards.enumerated()), id: \.offset) { index, card in
                        TextCarouselCard(card: card, index: index, enabled: enabled, onCardTap: onCardTap)
                    }
                }
            }
            if !content.dynamicButtons.isEmpty {
                Spacer().frame(height: 10)
                FlowLayout(spacing: 8) {
                    ForEach(Array(content.dynamicButtons.enumerated()), id: \.offset) { i, button in
                        QuickReplyButton(text: button.title, enabled: enabled, selected: false) {
                            onCardTap(button.title, -(i + 1), button.componentUuid ?? button.targetId)
                        }
                    }
                }
            }
        }
    }
}

@available(iOS 16.0, *)
private struct TextCarouselCard: View {
    @Environment(\.chat360Colors) private var colors
    @Environment(\.chat360Typography) private var typography
    @Environment(\.openURL) private var openURL

    let card: BotContent.TextCarousel.Card
    let index: Int
    let enabled: Bool
    let onCardTap: (String, Int, String?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let bgImage = card.bgImage, !bgImage.isBlank {
                AsyncImage(url: URL(string: bgImage)) { image in
                    image.resizable().aspectRatio(1.6, contentMode: .fill)
                } placeholder: {
                    Color.clear
                }
                .aspectRatio(1.6, contentMode: .fit)
                .clipped()
                Spacer().frame(height: 8)
            }
            if !(card.iconText?.isBlank ?? true) || !(card.iconUrl?.isBlank ?? true) {
                HStack {
                    if let iconUrl = card.iconUrl, !iconUrl.isBlank {
                        AsyncImage(url: URL(string: iconUrl)) { image in
                            image.resizable().aspectRatio(contentMode: .fit)
                        } placeholder: {
                            Color.clear
                        }
                        .frame(width: 16, height: 16)
                        Spacer().frame(width: 6)
                    }
                    if let iconText = card.iconText {
                        Text(iconText).font(typography.textFamily.font(size: 12)).foregroundColor(colors.textSecondary)
                    }
                }
                Spacer().frame(height: 6)
            }
            if let content = card.content {
                Text(content).font(typography.textFamily.font(size: 14, weight: .medium)).foregroundColor(colors.textPrimary)
            }
            if let footerText = card.footerText {
                Spacer().frame(height: 4)
                Text(footerText).font(typography.textFamily.font(size: 12)).foregroundColor(colors.textSecondary)
            }
            if card.ctaButtons.count == 2 {
                Spacer().frame(height: 8)
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
                                .font(typography.textFamily.font(size: 12))
                                .foregroundColor(colors.accentContrast)
                                .frame(width: 90)
                                .padding(.vertical, 8)
                                .background(colors.accent)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .disabled(!enabled)
                    }
                }
            }
            ForEach(Array(card.buttons.enumerated()), id: \.offset) { _, button in
                Spacer().frame(height: 6)
                QuickReplyButton(text: button.label, enabled: enabled, selected: false) {
                    onCardTap(button.label, index, button.link)
                }
            }
        }
        .padding(12)
        .frame(width: 220, alignment: .topLeading)
        .background(card.bgColor?.toChat360Color() ?? colors.cardBackground)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(colors.cardBorder, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .contentShape(Rectangle())
        .onTapGesture {
            guard enabled, let redirectLink = card.redirectLink else { return }
            if card.redirectType == "link", let url = URL(string: redirectLink) {
                openURL(url)
            } else {
                onCardTap(card.content ?? (card.name ?? ""), index, redirectLink)
            }
        }
    }
}
