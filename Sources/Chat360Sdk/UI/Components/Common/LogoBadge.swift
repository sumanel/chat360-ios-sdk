import SwiftUI

@available(iOS 15.0, *)
public struct BrandLogo: View {
    @Environment(\.chat360Branding) private var branding
    @Environment(\.chat360ThemeController) private var themeController
    @Environment(\.colorScheme) private var colorScheme

    public init() {}

    private var isDark: Bool {
        themeController?.isDarkTheme ?? (colorScheme == .dark)
    }

    public var body: some View {
        switch branding.logo {
        case .resource(let light, let dark):
            Image(isDark ? dark : light)
                .resizable()
                .aspectRatio(contentMode: .fit)
        case .remote(let url):
            AsyncImage(url: URL(string: url)) { image in
                image.resizable().aspectRatio(contentMode: .fit)
            } placeholder: {
                Color.clear
            }
        case nil:
            EmptyView()
        }
    }
}

@available(iOS 15.0, *)
public struct LogoBadge: View {
    @Environment(\.chat360Colors) private var colors
    @Environment(\.chat360Typography) private var typography
    @Environment(\.chat360Branding) private var branding
    @Environment(\.chat360ThemeController) private var themeController
    @Environment(\.colorScheme) private var colorScheme

    private let size: CGFloat
    private let cornerRadius: CGFloat
    private let overrideName: String?
    private let overrideAvatarUrl: String?

    public init(size: CGFloat, cornerRadius: CGFloat = 6, overrideName: String? = nil, overrideAvatarUrl: String? = nil) {
        self.size = size
        self.cornerRadius = cornerRadius
        self.overrideName = overrideName
        self.overrideAvatarUrl = overrideAvatarUrl
    }

    private var isDark: Bool {
        themeController?.isDarkTheme ?? (colorScheme == .dark)
    }

    private func initial(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).first.map { String($0).uppercased() } ?? "?"
    }

    public var body: some View {
        ZStack {
            if let overrideAvatarUrl, !overrideAvatarUrl.isBlank {
                AsyncImage(url: URL(string: overrideAvatarUrl)) { image in
                    image.resizable().aspectRatio(contentMode: .fit)
                } placeholder: {
                    Color.clear
                }
                .padding(size / 6)
            } else if let overrideName, !overrideName.isBlank {
                Text(initial(overrideName))
                    .font(typography.headFamily.font(size: size / 2, weight: .semibold))
                    .foregroundColor(colors.accent)
            } else {
                switch branding.logo {
                case .resource(let light, let dark):
                    Image(isDark ? dark : light)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .padding(size / 6)
                case .remote(let url):
                    AsyncImage(url: URL(string: url)) { image in
                        image.resizable().aspectRatio(contentMode: .fit)
                    } placeholder: {
                        Color.clear
                    }
                    .padding(size / 6)
                case nil:
                    Text(initial(branding.botTitle))
                        .font(typography.headFamily.font(size: size / 2, weight: .semibold))
                        .foregroundColor(colors.accent)
                }
            }
        }
        .frame(width: size, height: size)
        .background(colors.background)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .overlay(RoundedRectangle(cornerRadius: cornerRadius).stroke(colors.line, lineWidth: 1))
    }
}
