import SwiftUI

/// Maps the bot's server-side appearance config onto `Chat360ColorOverrides`/logo - this is the
/// "other values fetched from the API as per customization" layer, applied on top of whichever
/// theme preset (default/custom) the host app picked.
extension BotAppearanceDetails {
    func toColorOverrides() -> Chat360ColorOverrides {
        Chat360ColorOverrides(
            accent: chatboxHeader?.primarychatboxHeaderColor?.toColorOrNull(),
            background: (botBackgroundColor ?? primaryBackgroundColor)?.toColorOrNull(),
            bubbleUserBackground: userMessageBoxColor?.toColorOrNull(),
            bubbleUserText: userTextColor?.toColorOrNull(),
            bubbleAiBackground: botMessageBoxColor?.toColorOrNull(),
            bubbleAiText: botTextColor?.toColorOrNull(),
            statusBar: (chatboxHeader?.primarychatboxHeaderColor ?? chatboxHeader?.secondaryChatboxHeaderColor)?.toColorOrNull()
        )
    }

    /// A remote logo, only if the appearance response actually supplied one.
    func toLogoOverride() -> Chat360Logo? {
        guard let avatar = chatboxHeader?.chatboxAvatar, !avatar.isEmpty else { return nil }
        return .remote(url: avatar)
    }
}

/// Parses a "#RRGGBB"/"#AARRGGBB" hex string - shared by appearance-API overrides and any
/// bot-supplied color (e.g. TEXT_CAROUSEL card colors).
extension String {
    func toColorOrNull() -> Color? {
        guard hasPrefix("#") else { return nil }
        let hex = String(dropFirst())
        let argbHex: String
        switch hex.count {
        case 6: argbHex = "FF" + hex
        case 8: argbHex = hex
        default: return nil
        }
        guard let value = UInt32(argbHex, radix: 16) else { return nil }
        let alpha = Double((value >> 24) & 0xFF) / 255
        let red = Double((value >> 16) & 0xFF) / 255
        let green = Double((value >> 8) & 0xFF) / 255
        let blue = Double(value & 0xFF) / 255
        return Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }
}
