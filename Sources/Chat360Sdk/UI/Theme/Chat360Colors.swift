import SwiftUI

@available(iOS 13.0, *)
public struct Chat360Colors: Equatable {
    public var accent: Color
    public var accentContrast: Color
    public var background: Color
    public var backgroundElevated: Color
    public var backgroundSunken: Color
    public var line: Color
    public var textPrimary: Color
    public var textSecondary: Color
    public var textDisabled: Color
    public var bubbleUserBackground: Color
    public var bubbleUserText: Color
    public var bubbleAiBackground: Color
    public var bubbleAiText: Color
    public var cardBackground: Color
    public var cardBorder: Color
    public var inputBackground: Color
    public var inputBorder: Color
    public var statusBar: Color

    public init(
        accent: Color, accentContrast: Color, background: Color, backgroundElevated: Color, backgroundSunken: Color,
        line: Color, textPrimary: Color, textSecondary: Color, textDisabled: Color, bubbleUserBackground: Color,
        bubbleUserText: Color, bubbleAiBackground: Color, bubbleAiText: Color, cardBackground: Color, cardBorder: Color,
        inputBackground: Color, inputBorder: Color, statusBar: Color
    ) {
        self.accent = accent
        self.accentContrast = accentContrast
        self.background = background
        self.backgroundElevated = backgroundElevated
        self.backgroundSunken = backgroundSunken
        self.line = line
        self.textPrimary = textPrimary
        self.textSecondary = textSecondary
        self.textDisabled = textDisabled
        self.bubbleUserBackground = bubbleUserBackground
        self.bubbleUserText = bubbleUserText
        self.bubbleAiBackground = bubbleAiBackground
        self.bubbleAiText = bubbleAiText
        self.cardBackground = cardBackground
        self.cardBorder = cardBorder
        self.inputBackground = inputBackground
        self.inputBorder = inputBorder
        self.statusBar = statusBar
    }
}

@available(iOS 13.0, *)
public struct Chat360ColorOverrides {
    public var accent: Color?
    public var accentContrast: Color?
    public var background: Color?
    public var backgroundElevated: Color?
    public var backgroundSunken: Color?
    public var line: Color?
    public var textPrimary: Color?
    public var textSecondary: Color?
    public var textDisabled: Color?
    public var bubbleUserBackground: Color?
    public var bubbleUserText: Color?
    public var bubbleAiBackground: Color?
    public var bubbleAiText: Color?
    public var cardBackground: Color?
    public var cardBorder: Color?
    public var inputBackground: Color?
    public var inputBorder: Color?
    public var statusBar: Color?

    public init(
        accent: Color? = nil, accentContrast: Color? = nil, background: Color? = nil, backgroundElevated: Color? = nil,
        backgroundSunken: Color? = nil, line: Color? = nil, textPrimary: Color? = nil, textSecondary: Color? = nil,
        textDisabled: Color? = nil, bubbleUserBackground: Color? = nil, bubbleUserText: Color? = nil,
        bubbleAiBackground: Color? = nil, bubbleAiText: Color? = nil, cardBackground: Color? = nil, cardBorder: Color? = nil,
        inputBackground: Color? = nil, inputBorder: Color? = nil, statusBar: Color? = nil
    ) {
        self.accent = accent
        self.accentContrast = accentContrast
        self.background = background
        self.backgroundElevated = backgroundElevated
        self.backgroundSunken = backgroundSunken
        self.line = line
        self.textPrimary = textPrimary
        self.textSecondary = textSecondary
        self.textDisabled = textDisabled
        self.bubbleUserBackground = bubbleUserBackground
        self.bubbleUserText = bubbleUserText
        self.bubbleAiBackground = bubbleAiBackground
        self.bubbleAiText = bubbleAiText
        self.cardBackground = cardBackground
        self.cardBorder = cardBorder
        self.inputBackground = inputBackground
        self.inputBorder = inputBorder
        self.statusBar = statusBar
    }
}

@available(iOS 13.0, *)
extension Chat360Colors {
    public func applyingOverrides(_ overrides: Chat360ColorOverrides?) -> Chat360Colors {
        guard let overrides else { return self }
        var result = self
        result.accent = overrides.accent ?? accent
        result.accentContrast = overrides.accentContrast ?? accentContrast
        result.background = overrides.background ?? background
        result.backgroundElevated = overrides.backgroundElevated ?? backgroundElevated
        result.backgroundSunken = overrides.backgroundSunken ?? backgroundSunken
        result.line = overrides.line ?? line
        result.textPrimary = overrides.textPrimary ?? textPrimary
        result.textSecondary = overrides.textSecondary ?? textSecondary
        result.textDisabled = overrides.textDisabled ?? textDisabled
        result.bubbleUserBackground = overrides.bubbleUserBackground ?? bubbleUserBackground
        result.bubbleUserText = overrides.bubbleUserText ?? bubbleUserText
        result.bubbleAiBackground = overrides.bubbleAiBackground ?? bubbleAiBackground
        result.bubbleAiText = overrides.bubbleAiText ?? bubbleAiText
        result.cardBackground = overrides.cardBackground ?? cardBackground
        result.cardBorder = overrides.cardBorder ?? cardBorder
        result.inputBackground = overrides.inputBackground ?? inputBackground
        result.inputBorder = overrides.inputBorder ?? inputBorder
        result.statusBar = overrides.statusBar ?? statusBar
        return result
    }
}

@available(iOS 13.0, *)
public let defaultLightColors = Chat360Colors(
    accent: Color(red: 0x25 / 255, green: 0x63 / 255, blue: 0xEB / 255),
    accentContrast: Color(red: 1, green: 1, blue: 1),
    background: Color(red: 0xF7 / 255, green: 0xF8 / 255, blue: 0xFA / 255),
    backgroundElevated: Color(red: 1, green: 1, blue: 1),
    backgroundSunken: Color(red: 0xF0 / 255, green: 0xF1 / 255, blue: 0xF4 / 255),
    line: Color(red: 0xE2 / 255, green: 0xE5 / 255, blue: 0xEA / 255),
    textPrimary: Color(red: 0x1A / 255, green: 0x1D / 255, blue: 0x21 / 255),
    textSecondary: Color(red: 0x6B / 255, green: 0x72 / 255, blue: 0x80 / 255),
    textDisabled: Color(red: 0xC7 / 255, green: 0xCB / 255, blue: 0xD1 / 255),
    bubbleUserBackground: Color(red: 0x25 / 255, green: 0x63 / 255, blue: 0xEB / 255),
    bubbleUserText: Color(red: 1, green: 1, blue: 1),
    bubbleAiBackground: Color(red: 1, green: 1, blue: 1),
    bubbleAiText: Color(red: 0x1A / 255, green: 0x1D / 255, blue: 0x21 / 255),
    cardBackground: Color(red: 1, green: 1, blue: 1),
    cardBorder: Color(red: 0xE2 / 255, green: 0xE5 / 255, blue: 0xEA / 255),
    inputBackground: Color(red: 1, green: 1, blue: 1),
    inputBorder: Color(red: 0xD1 / 255, green: 0xD5 / 255, blue: 0xDB / 255),
    statusBar: Color(red: 0x25 / 255, green: 0x63 / 255, blue: 0xEB / 255)
)

@available(iOS 13.0, *)
public let defaultDarkColors = Chat360Colors(
    accent: Color(red: 0x6D / 255, green: 0x9B / 255, blue: 0xFF / 255),
    accentContrast: Color(red: 0x0B / 255, green: 0x0D / 255, blue: 0x10 / 255),
    background: Color(red: 0x0F / 255, green: 0x11 / 255, blue: 0x15 / 255),
    backgroundElevated: Color(red: 0x18 / 255, green: 0x1B / 255, blue: 0x20 / 255),
    backgroundSunken: Color(red: 0x14 / 255, green: 0x16 / 255, blue: 0x1A / 255),
    line: Color(red: 0x2A / 255, green: 0x2E / 255, blue: 0x35 / 255),
    textPrimary: Color(red: 0xF2 / 255, green: 0xF3 / 255, blue: 0xF5 / 255),
    textSecondary: Color(red: 0x9A / 255, green: 0xA1 / 255, blue: 0xAC / 255),
    textDisabled: Color(red: 0x4B / 255, green: 0x50 / 255, blue: 0x58 / 255),
    bubbleUserBackground: Color(red: 0x25 / 255, green: 0x63 / 255, blue: 0xEB / 255),
    bubbleUserText: Color(red: 1, green: 1, blue: 1),
    bubbleAiBackground: Color(red: 0x1E / 255, green: 0x21 / 255, blue: 0x27 / 255),
    bubbleAiText: Color(red: 0xF2 / 255, green: 0xF3 / 255, blue: 0xF5 / 255),
    cardBackground: Color(red: 0x18 / 255, green: 0x1B / 255, blue: 0x20 / 255),
    cardBorder: Color(red: 0x2A / 255, green: 0x2E / 255, blue: 0x35 / 255),
    inputBackground: Color(red: 0x18 / 255, green: 0x1B / 255, blue: 0x20 / 255),
    inputBorder: Color(red: 0x32 / 255, green: 0x36 / 255, blue: 0x3E / 255),
    statusBar: Color(red: 0x0B / 255, green: 0x0D / 255, blue: 0x10 / 255)
)

@available(iOS 13.0, *)
public struct Chat360ColorsKey: EnvironmentKey {
    public static let defaultValue: Chat360Colors = defaultLightColors
}

@available(iOS 13.0, *)
extension EnvironmentValues {
    public var chat360Colors: Chat360Colors {
        get { self[Chat360ColorsKey.self] }
        set { self[Chat360ColorsKey.self] = newValue }
    }
}
