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
