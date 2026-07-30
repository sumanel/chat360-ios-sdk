import SwiftUI

/// Generic color-token contract for the whole chat UI. Every component reads colors through the
/// `\.chat360Colors` environment value - never a brand name - so a new brand is "provide a new
/// Chat360Colors pair", never a code change in a message/input/chrome component.
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
        accent: Color, accentContrast: Color,
        background: Color, backgroundElevated: Color, backgroundSunken: Color,
        line: Color,
        textPrimary: Color, textSecondary: Color, textDisabled: Color,
        bubbleUserBackground: Color, bubbleUserText: Color,
        bubbleAiBackground: Color, bubbleAiText: Color,
        cardBackground: Color, cardBorder: Color,
        inputBackground: Color, inputBorder: Color,
        statusBar: Color
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

/// All-nullable mirror of `Chat360Colors`, for partial overrides coming from a client's own
/// config or the bot's server-side appearance API - only the tokens actually present override
/// the preset's base values, everything else falls through.
public struct Chat360ColorOverrides: Equatable {
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
        accent: Color? = nil, accentContrast: Color? = nil,
        background: Color? = nil, backgroundElevated: Color? = nil, backgroundSunken: Color? = nil,
        line: Color? = nil,
        textPrimary: Color? = nil, textSecondary: Color? = nil, textDisabled: Color? = nil,
        bubbleUserBackground: Color? = nil, bubbleUserText: Color? = nil,
        bubbleAiBackground: Color? = nil, bubbleAiText: Color? = nil,
        cardBackground: Color? = nil, cardBorder: Color? = nil,
        inputBackground: Color? = nil, inputBorder: Color? = nil,
        statusBar: Color? = nil
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

public extension Chat360Colors {
    func applyingOverrides(_ overrides: Chat360ColorOverrides?) -> Chat360Colors {
        guard let overrides else { return self }
        return Chat360Colors(
            accent: overrides.accent ?? accent,
            accentContrast: overrides.accentContrast ?? accentContrast,
            background: overrides.background ?? background,
            backgroundElevated: overrides.backgroundElevated ?? backgroundElevated,
            backgroundSunken: overrides.backgroundSunken ?? backgroundSunken,
            line: overrides.line ?? line,
            textPrimary: overrides.textPrimary ?? textPrimary,
            textSecondary: overrides.textSecondary ?? textSecondary,
            textDisabled: overrides.textDisabled ?? textDisabled,
            bubbleUserBackground: overrides.bubbleUserBackground ?? bubbleUserBackground,
            bubbleUserText: overrides.bubbleUserText ?? bubbleUserText,
            bubbleAiBackground: overrides.bubbleAiBackground ?? bubbleAiBackground,
            bubbleAiText: overrides.bubbleAiText ?? bubbleAiText,
            cardBackground: overrides.cardBackground ?? cardBackground,
            cardBorder: overrides.cardBorder ?? cardBorder,
            inputBackground: overrides.inputBackground ?? inputBackground,
            inputBorder: overrides.inputBorder ?? inputBorder,
            statusBar: overrides.statusBar ?? statusBar
        )
    }
}

/// The library's own brand-neutral default (a simple blue/gray palette) - used whenever a host
/// app doesn't request a specific preset and hasn't supplied its own colors.
public let DefaultLightColors = Chat360Colors(
    accent: Color(red: 0x25 / 255, green: 0x63 / 255, blue: 0xEB / 255),
    accentContrast: .white,
    background: Color(red: 0xF7 / 255, green: 0xF8 / 255, blue: 0xFA / 255),
    backgroundElevated: .white,
    backgroundSunken: Color(red: 0xF0 / 255, green: 0xF1 / 255, blue: 0xF4 / 255),
    line: Color(red: 0xE2 / 255, green: 0xE5 / 255, blue: 0xEA / 255),
    textPrimary: Color(red: 0x1A / 255, green: 0x1D / 255, blue: 0x21 / 255),
    textSecondary: Color(red: 0x6B / 255, green: 0x72 / 255, blue: 0x80 / 255),
    textDisabled: Color(red: 0xC7 / 255, green: 0xCB / 255, blue: 0xD1 / 255),
    bubbleUserBackground: Color(red: 0x25 / 255, green: 0x63 / 255, blue: 0xEB / 255),
    bubbleUserText: .white,
    bubbleAiBackground: .white,
    bubbleAiText: Color(red: 0x1A / 255, green: 0x1D / 255, blue: 0x21 / 255),
    cardBackground: .white,
    cardBorder: Color(red: 0xE2 / 255, green: 0xE5 / 255, blue: 0xEA / 255),
    inputBackground: .white,
    inputBorder: Color(red: 0xD1 / 255, green: 0xD5 / 255, blue: 0xDB / 255),
    statusBar: Color(red: 0x25 / 255, green: 0x63 / 255, blue: 0xEB / 255)
)

public let DefaultDarkColors = Chat360Colors(
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
    bubbleUserText: .white,
    bubbleAiBackground: Color(red: 0x1E / 255, green: 0x21 / 255, blue: 0x27 / 255),
    bubbleAiText: Color(red: 0xF2 / 255, green: 0xF3 / 255, blue: 0xF5 / 255),
    cardBackground: Color(red: 0x18 / 255, green: 0x1B / 255, blue: 0x20 / 255),
    cardBorder: Color(red: 0x2A / 255, green: 0x2E / 255, blue: 0x35 / 255),
    inputBackground: Color(red: 0x18 / 255, green: 0x1B / 255, blue: 0x20 / 255),
    inputBorder: Color(red: 0x32 / 255, green: 0x36 / 255, blue: 0x3E / 255),
    statusBar: Color(red: 0x0B / 255, green: 0x0D / 255, blue: 0x10 / 255)
)
