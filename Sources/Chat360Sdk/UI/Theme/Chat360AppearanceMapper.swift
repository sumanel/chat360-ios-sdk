import SwiftUI

@available(iOS 13.0, *)
extension BotAppearanceDetails {
    public func toColorOverrides() -> Chat360ColorOverrides {
        Chat360ColorOverrides(
            accent: chatboxHeader?.primarychatboxHeaderColor?.toChat360Color(),
            background: (botBackgroundColor ?? primaryBackgroundColor)?.toChat360Color(),
            bubbleUserBackground: userMessageBoxColor?.toChat360Color(),
            bubbleUserText: userTextColor?.toChat360Color(),
            bubbleAiBackground: botMessageBoxColor?.toChat360Color(),
            bubbleAiText: botTextColor?.toChat360Color(),
            statusBar: (chatboxHeader?.primarychatboxHeaderColor ?? chatboxHeader?.secondaryChatboxHeaderColor)?.toChat360Color()
        )
    }

    public func toLogoOverride() -> Chat360Logo? {
        guard let avatar = chatboxHeader?.chatboxAvatar, !avatar.isBlank else { return nil }
        return .remote(url: avatar)
    }
}

/// The logo to show: the host's configured one always wins, so a brand's own logo (Hyundai's) is never replaced by the
/// bot's server-side avatar. The server's logo only fills in when the host configured none.
@available(iOS 13.0, *)
public func resolveLogo(configured: Chat360Logo?, fromServer: Chat360Logo?) -> Chat360Logo? {
    configured ?? fromServer
}

@available(iOS 13.0, *)
extension ChatUiState {
    /// Applies a (re)loaded bot appearance. The logo is sticky: a failed fetch (`details == nil`, e.g. right after a
    /// dropped socket or a wake from sleep) or a response with no logo keeps the one already resolved instead of
    /// falling back to whatever sits underneath.
    mutating func applyAppearance(_ details: BotAppearanceDetails?, chatboxName: String?) {
        colorOverrides = details?.toColorOverrides()
        logoOverride = details?.toLogoOverride() ?? logoOverride
        botTitleOverride = chatboxName.flatMap { $0.isBlank ? nil : $0 }
        feedbackConfig = details?.feedback_config ?? feedbackConfig
    }
}

@available(iOS 13.0, *)
extension String {
    public func toChat360Color() -> Color? {
        guard hasPrefix("#") else { return nil }
        let hex = String(dropFirst())
        let argbHex: String
        switch hex.count {
        case 6: argbHex = "FF" + hex
        case 8: argbHex = hex
        default: return nil
        }
        guard let argb = UInt32(argbHex, radix: 16) else { return nil }
        let alpha = Double((argb >> 24) & 0xFF) / 255
        let red = Double((argb >> 16) & 0xFF) / 255
        let green = Double((argb >> 8) & 0xFF) / 255
        let blue = Double(argb & 0xFF) / 255
        return Color(red: red, green: green, blue: blue, opacity: alpha)
    }
}
