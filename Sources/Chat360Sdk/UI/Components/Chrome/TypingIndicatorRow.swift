import SwiftUI

struct TypingIndicatorRow: View {
    @Environment(\.chat360Colors) private var colors
    @Environment(\.chat360Typography) private var typography
    @Environment(\.chat360Branding) private var branding

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            LogoBadge(size: 28)
            Text("\(branding.botTitle) is typing…")
                .font(textFont(size: 13))
                .foregroundColor(colors.textSecondary)
        }
    }

    private func textFont(size: CGFloat) -> Font {
        if let name = typography.textFontName { return .custom(name, size: size) }
        return .system(size: size)
    }
}
