import SwiftUI

@available(iOS 15.0, *)
public struct LinkCardContent: View {
    @Environment(\.chat360Colors) private var colors
    @Environment(\.chat360Typography) private var typography
    @Environment(\.openURL) private var openURL

    private let caption: String
    private let content: BotContent.LinkCard

    public init(caption: String, content: BotContent.LinkCard) {
        self.caption = caption
        self.content = content
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !caption.isEmpty { PlainTextContent(caption) }
            Text(content.url)
                .font(typography.textFamily.font(size: 13))
                .foregroundColor(colors.accent)
                .lineLimit(2)
                .padding(12)
                .background(colors.cardBackground)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(colors.cardBorder, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .onTapGesture {
                    if let url = URL(string: content.url) { openURL(url) }
                }
        }
    }
}
