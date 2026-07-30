import SwiftUI

/// Horizontally scrolling cards for a CAROUSEL node; a tap opens the card's link externally.
struct CarouselContent: View {
    var caption: String
    var content: BotContent.Carousel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !caption.isEmpty { PlainTextContent(text: caption) }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Array(content.cards.enumerated()), id: \.offset) { _, card in
                        CarouselCardView(card: card)
                    }
                }
            }
        }
    }
}

private struct CarouselCardView: View {
    var card: BotContent.Carousel.Card

    @Environment(\.chat360Colors) private var colors
    @Environment(\.chat360Typography) private var typography
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button(action: {
            if let link = card.link, let url = URL(string: link) { openURL(url) }
        }) {
            VStack(alignment: .leading, spacing: 0) {
                AsyncImage(url: URL(string: card.imageUrl)) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    colors.backgroundSunken
                }
                .frame(width: 200, height: 200)
                .clipped()

                VStack(alignment: .leading, spacing: 2) {
                    if let heading = card.heading {
                        Text(heading).font(textFont(size: 14)).fontWeight(.semibold).foregroundColor(colors.textPrimary).lineLimit(1)
                    }
                    if let caption = card.caption {
                        Text(caption).font(textFont(size: 12)).foregroundColor(colors.textSecondary).lineLimit(3)
                    }
                }
                .padding(10)
            }
            .frame(width: 200)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(colors.cardBorder, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .disabled(card.link == nil)
    }

    private func textFont(size: CGFloat) -> Font {
        if let name = typography.textFontName { return .custom(name, size: size) }
        return .system(size: size)
    }
}
