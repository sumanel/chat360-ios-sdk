import SwiftUI

@available(iOS 15.0, *)
public struct WelcomeSplash: View {
    @Environment(\.chat360Colors) private var colors
    @Environment(\.chat360Typography) private var typography
    @Environment(\.chat360Branding) private var branding

    // Set when a brand-new, still-empty conversation can't actually be started right now (e.g.
    // maintenance mode) - swaps the normal welcome copy for that reason instead of inviting the
    // user into a chat that has nowhere to go.
    private let unavailableMessage: String?

    public init(unavailableMessage: String? = nil) {
        self.unavailableMessage = unavailableMessage
    }

    public var body: some View {
        GeometryReader { proxy in
            VStack {
                Spacer()
                VStack(spacing: 0) {
                    if branding.logo != nil {
                        BrandLogo()
                            .frame(width: branding.welcomeLogoSize ?? proxy.size.width * 0.5)
                    } else {
                        LogoBadge(size: branding.welcomeLogoSize ?? 84, cornerRadius: 20)
                    }
                    Spacer().frame(height: 24)
                    if let unavailableMessage {
                        Text(unavailableMessage)
                            .font(typography.headFamily.font(size: 20, weight: .semibold))
                            .foregroundColor(colors.textPrimary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 8)
                    } else {
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
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 32)
                Spacer()
            }
        }
    }
}
