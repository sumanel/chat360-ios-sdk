import SwiftUI

struct PlainTextContent: View {
    var text: String

    @Environment(\.chat360Colors) private var colors
    @Environment(\.chat360Typography) private var typography

    var body: some View {
        if !text.isEmpty {
            Text(text.toAttributedString(linkColor: colors.accent))
                .font(bodyFont)
                .foregroundColor(colors.bubbleAiText)
                .lineSpacing(7)
        }
    }

    private var bodyFont: Font {
        if let name = typography.textFontName { return .custom(name, size: 15) }
        return .system(size: 15)
    }
}
