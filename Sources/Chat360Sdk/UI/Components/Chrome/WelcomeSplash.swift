import SwiftUI

struct WelcomeSplash: View {
    @Environment(\.chat360Colors) private var colors
    @Environment(\.chat360Typography) private var typography
    @Environment(\.chat360Branding) private var branding

    var body: some View {
        VStack(spacing: 0) {
            LogoBadge(size: 84, cornerRadius: 20)
            Spacer().frame(height: 24)
            Text(branding.welcomeHeading)
                .font(headFont(size: 24))
                .fontWeight(.semibold)
                .foregroundColor(colors.textPrimary)
            Spacer().frame(height: 12)
            Text(branding.disclaimerText)
                .font(textFont(size: 13))
                .foregroundColor(colors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 32)
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
