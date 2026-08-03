import SwiftUI

/// Named starting points a host app (or our own demo) can pick from. `.custom` means "use the
/// colors/typography/branding I'm supplying" - this is how any brand-specific look (a client's
/// own palette, logo, fonts) is configured; the library itself never bundles a named brand
/// preset, only the brand-neutral `.standard`.
public enum Chat360ThemePreset: Equatable {
    case standard
    case custom
}

private struct Chat360ColorsKey: EnvironmentKey {
    static let defaultValue = DefaultLightColors
}

private struct Chat360TypographyKey: EnvironmentKey {
    static let defaultValue = DefaultChat360Typography
}

private struct Chat360BrandingKey: EnvironmentKey {
    static let defaultValue = DefaultBranding
}

private struct Chat360InputBarConfigKey: EnvironmentKey {
    static let defaultValue = DefaultInputBarConfig
}

public extension EnvironmentValues {
    var chat360Colors: Chat360Colors {
        get { self[Chat360ColorsKey.self] }
        set { self[Chat360ColorsKey.self] = newValue }
    }

    var chat360Typography: Chat360Typography {
        get { self[Chat360TypographyKey.self] }
        set { self[Chat360TypographyKey.self] = newValue }
    }

    var chat360Branding: Chat360Branding {
        get { self[Chat360BrandingKey.self] }
        set { self[Chat360BrandingKey.self] = newValue }
    }

    var chat360InputBarConfig: Chat360InputBarConfig {
        get { self[Chat360InputBarConfigKey.self] }
        set { self[Chat360InputBarConfigKey.self] = newValue }
    }
}

/// Resolves a preset (or a client's own custom colors/typography/branding) to the
/// Colors/Typography/Branding every component reads via the environment. `colorOverrides`
/// applies on *top* of whichever base preset is chosen - this is the seam the bot's own
/// server-side appearance API customizes through, independent of which preset a host app picked.
private struct Chat360ThemeModifier: ViewModifier {
    var preset: Chat360ThemePreset
    var customLightColors: Chat360Colors?
    var customDarkColors: Chat360Colors?
    var customTypography: Chat360Typography?
    var customBranding: Chat360Branding?
    var colorOverrides: Chat360ColorOverrides?
    /// Not preset-dependent (unlike colors/typography/branding) - it's a behavior toggle set, not
    /// a look, so it applies as-is regardless of `.standard` vs `.custom`.
    var inputBarConfig: Chat360InputBarConfig

    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let light: Chat360Colors
        let dark: Chat360Colors
        let typography: Chat360Typography
        let branding: Chat360Branding
        switch preset {
        case .custom:
            light = customLightColors ?? DefaultLightColors
            dark = customDarkColors ?? DefaultDarkColors
            typography = customTypography ?? DefaultChat360Typography
            branding = customBranding ?? DefaultBranding
        case .standard:
            light = DefaultLightColors
            dark = DefaultDarkColors
            typography = DefaultChat360Typography
            branding = DefaultBranding
        }
        let resolvedColors = (colorScheme == .dark ? dark : light).applyingOverrides(colorOverrides)

        return content
            .environment(\.chat360Colors, resolvedColors)
            .environment(\.chat360Typography, typography)
            .environment(\.chat360Branding, branding)
            .environment(\.chat360InputBarConfig, inputBarConfig)
    }
}

public extension View {
    func chat360Theme(
        preset: Chat360ThemePreset = .standard,
        customLightColors: Chat360Colors? = nil,
        customDarkColors: Chat360Colors? = nil,
        customTypography: Chat360Typography? = nil,
        customBranding: Chat360Branding? = nil,
        colorOverrides: Chat360ColorOverrides? = nil,
        inputBarConfig: Chat360InputBarConfig = Chat360InputBarConfig()
    ) -> some View {
        modifier(Chat360ThemeModifier(
            preset: preset,
            customLightColors: customLightColors,
            customDarkColors: customDarkColors,
            customTypography: customTypography,
            customBranding: customBranding,
            colorOverrides: colorOverrides,
            inputBarConfig: inputBarConfig
        ))
    }
}
