import SwiftUI

/// Shared "error/destructive" red, reused for failed-message text.
let activeRed = Color(red: 0xE6 / 255, green: 0x33 / 255, blue: 0x12 / 255)

struct StatusBanner: View {
    var text: String
    var emphasized: Bool

    @Environment(\.chat360Colors) private var colors
    @Environment(\.chat360Typography) private var typography

    var body: some View {
        Text(text)
            .font(textFont(size: 13))
            .foregroundColor(emphasized ? activeRed : colors.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(colors.backgroundElevated)
    }

    private func textFont(size: CGFloat) -> Font {
        if let name = typography.textFontName { return .custom(name, size: size) }
        return .system(size: size)
    }
}
