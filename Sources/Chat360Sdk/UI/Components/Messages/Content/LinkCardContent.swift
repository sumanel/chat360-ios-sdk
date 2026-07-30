import SwiftUI

/// A small clickable card for a LINK node that also has its own question text.
struct LinkCardContent: View {
    var caption: String
    var content: BotContent.LinkCard

    @Environment(\.chat360Colors) private var colors
    @Environment(\.chat360Typography) private var typography
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !caption.isEmpty { PlainTextContent(text: caption) }
            Button(action: { if let url = URL(string: content.url) { openURL(url) } }) {
                Text(content.url)
                    .font(textFont(size: 13))
                    .foregroundColor(colors.accent)
                    .lineLimit(2)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(colors.cardBackground)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(colors.cardBorder, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
        }
    }

    private func textFont(size: CGFloat) -> Font {
        if let name = typography.textFontName { return .custom(name, size: size) }
        return .system(size: size)
    }
}
