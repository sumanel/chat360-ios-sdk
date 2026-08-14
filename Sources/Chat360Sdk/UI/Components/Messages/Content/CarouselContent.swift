import SwiftUI

@available(iOS 15.0, *)
public struct CarouselContent: View {
    private let caption: String
    private let content: BotContent.Carousel

    public init(caption: String, content: BotContent.Carousel) {
        self.caption = caption
        self.content = content
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !caption.isEmpty {
                PlainTextContent(caption)
                Spacer().frame(height: 8)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Array(content.cards.enumerated()), id: \.offset) { _, card in
                        CarouselCard(card: card)
                    }
                }
            }
        }
    }
}

@available(iOS 15.0, *)
private struct CarouselCard: View {
    @Environment(\.chat360Colors) private var colors
    @Environment(\.chat360Typography) private var typography
    @Environment(\.openURL) private var openURL
    let card: BotContent.Carousel.Card

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            AsyncImage(url: URL(string: card.imageUrl)) { image in
                image.resizable().aspectRatio(1, contentMode: .fill)
            } placeholder: {
                Color.clear
            }
            .aspectRatio(1, contentMode: .fit)
            .clipped()

            VStack(alignment: .leading, spacing: 2) {
                if let heading = card.heading {
                    Text(heading)
                        .font(typography.textFamily.font(size: 14, weight: .semibold))
                        .foregroundColor(colors.textPrimary)
                        .lineLimit(1)
                }
                if let caption = card.caption {
                    Text(caption)
                        .font(typography.textFamily.font(size: 12))
                        .foregroundColor(colors.textSecondary)
                        .lineLimit(3)
                }
            }
            .padding(10)
        }
        .frame(width: 200)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(colors.cardBorder, lineWidth: 1))
        .onTapGesture {
            if let link = card.link, let url = URL(string: link) { openURL(url) }
        }
    }
}
