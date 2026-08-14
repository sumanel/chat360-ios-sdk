import SwiftUI

@available(iOS 15.0, *)
public struct WelcomeSplash: View {
    @Environment(\.chat360Colors) private var colors
    @Environment(\.chat360Typography) private var typography
    @Environment(\.chat360Branding) private var branding

    public init() {}

    public var body: some View {
        GeometryReader { proxy in
            VStack {
                Spacer()
                VStack(spacing: 0) {
                    if branding.logo != nil {
                        BrandLogo()
                            .frame(width: proxy.size.width * 0.5)
                    } else {
                        LogoBadge(size: 84, cornerRadius: 20)
                    }
                    Spacer().frame(height: 24)
                    Text(branding.welcomeHeading)
                        .font(typography.headFamily.font(size: 20, weight: .semibold))
                        .foregroundColor(colors.textPrimary)
                    Spacer().frame(height: 12)
                    Text(branding.disclaimerText)
                        .font(typography.textFamily.font(size: 13))
                        .foregroundColor(colors.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 8)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 32)
                Spacer()
            }
        }
    }
}
