import SwiftUI

/// The bot's avatar, used in the welcome splash and as the row icon on every bot message. Reads
/// `\.chat360Branding` rather than taking a logo directly - a brand with no logo configured (the
/// generic default) falls back to a plain initial-letter badge instead of a broken image.
///
/// `overrideName`/`overrideAvatarUrl` let a live-chat message show the assigned human agent's
/// avatar/initial instead of the bot's, reusing the exact same badge styling.
struct LogoBadge: View {
    var size: CGFloat
    var cornerRadius: CGFloat = 6
    var overrideName: String?
    var overrideAvatarUrl: String?

    @Environment(\.chat360Colors) private var colors
    @Environment(\.chat360Typography) private var typography
    @Environment(\.chat360Branding) private var branding
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(colors.backgroundElevated)
                .overlay(RoundedRectangle(cornerRadius: cornerRadius).stroke(colors.line, lineWidth: 1))

            content
        }
        .frame(width: size, height: size)
    }

    @ViewBuilder
    private var content: some View {
        if let overrideAvatarUrl, !overrideAvatarUrl.isEmpty, let url = URL(string: overrideAvatarUrl) {
            AsyncImage(url: url) { image in
                image.resizable().scaledToFit()
            } placeholder: {
                Color.clear
            }
            .padding(size / 6)
        } else if let overrideName, !overrideName.isEmpty {
            initialText(overrideName)
        } else if let logo = branding.logo {
            switch logo {
            case .resource(let light, let dark):
                // TODO(Phase 9): once the package ships its own Assets.xcassets, load this from
                // Bundle.module instead of the host app's main bundle.
                Image(colorScheme == .dark ? (dark ?? light) : light)
                    .resizable()
                    .scaledToFit()
                    .padding(size / 6)
            case .remote(let urlString):
                if let url = URL(string: urlString) {
                    AsyncImage(url: url) { image in
                        image.resizable().scaledToFit()
                    } placeholder: {
                        Color.clear
                    }
                    .padding(size / 6)
                }
            }
        } else {
            initialText(branding.botTitle)
        }
    }

    private func initialText(_ source: String) -> some View {
        let letter = source.trimmingCharacters(in: .whitespaces).first.map { String($0).uppercased() } ?? "?"
        return Text(letter)
            .font(headFont(size: size / 2))
            .fontWeight(.semibold)
            .foregroundColor(colors.accent)
    }

    private func headFont(size: CGFloat) -> Font {
        if let name = typography.headFontName {
            return .custom(name, size: size)
        }
        return .system(size: size)
    }
}
