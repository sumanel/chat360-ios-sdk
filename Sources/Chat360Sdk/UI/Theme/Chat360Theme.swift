import SwiftUI

@available(iOS 13.0, *)
public enum Chat360ThemePreset {
    case `default`, custom
}

@available(iOS 14.0, *)
public final class Chat360ThemeController: ObservableObject {
    @Published public private(set) var isDarkTheme: Bool

    public init(isDarkTheme: Bool) {
        self.isDarkTheme = isDarkTheme
    }

    public func selectDarkTheme(_ isDark: Bool) {
        isDarkTheme = isDark
    }
}

@available(iOS 14.0, *)
public struct Chat360ThemeControllerKey: EnvironmentKey {
    public static let defaultValue: Chat360ThemeController? = nil
}

@available(iOS 14.0, *)
extension EnvironmentValues {
    public var chat360ThemeController: Chat360ThemeController? {
        get { self[Chat360ThemeControllerKey.self] }
        set { self[Chat360ThemeControllerKey.self] = newValue }
    }
}

@available(iOS 14.0, *)
private struct Chat360ThemeBundle {
    let light: Chat360Colors
    let dark: Chat360Colors
    let typography: Chat360Typography
    let branding: Chat360Branding
}

@available(iOS 14.0, *)
public struct Chat360Theme<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var themeController: Chat360ThemeController

    private let preset: Chat360ThemePreset
    private let customLightColors: Chat360Colors?
    private let customDarkColors: Chat360Colors?
    private let customTypography: Chat360Typography?
    private let customBranding: Chat360Branding?
    private let colorOverrides: Chat360ColorOverrides?
    private let config: Chat360UIConfig
    private let content: () -> Content

    public init(
        preset: Chat360ThemePreset = .default,
        customLightColors: Chat360Colors? = nil,
        customDarkColors: Chat360Colors? = nil,
        customTypography: Chat360Typography? = nil,
        customBranding: Chat360Branding? = nil,
        colorOverrides: Chat360ColorOverrides? = nil,
        config: Chat360UIConfig = Chat360UIConfig(),
        darkTheme: Bool? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.preset = preset
        self.customLightColors = customLightColors
        self.customDarkColors = customDarkColors
        self.customTypography = customTypography
        self.customBranding = customBranding
        self.colorOverrides = colorOverrides
        self.config = config
        self.content = content

        let initialDarkTheme: Bool
        switch config.theme.defaultTheme {
        case .light: initialDarkTheme = false
        case .dark: initialDarkTheme = true
        case .system: initialDarkTheme = darkTheme ?? false
        }
        _themeController = StateObject(wrappedValue: Chat360ThemeController(isDarkTheme: initialDarkTheme))
    }

    public var body: some View {
        let bundle: Chat360ThemeBundle
        switch preset {
        case .custom:
            bundle = Chat360ThemeBundle(
                light: customLightColors ?? defaultLightColors,
                dark: customDarkColors ?? defaultDarkColors,
                typography: customTypography ?? defaultChat360Typography,
                branding: customBranding ?? defaultBranding
            )
        case .default:
            bundle = Chat360ThemeBundle(light: defaultLightColors, dark: defaultDarkColors, typography: defaultChat360Typography, branding: defaultBranding)
        }

        let selectedColors = themeController.isDarkTheme ? bundle.dark : bundle.light
        let base = selectedColors.applyingOverrides(colorOverrides)

        var resolvedColors = base
        resolvedColors.accent = config.branding.primaryColor ?? base.accent
        resolvedColors.textSecondary = config.branding.secondaryColor ?? base.textSecondary

        var resolvedBranding = bundle.branding
        resolvedBranding.botTitle = config.branding.botName ?? bundle.branding.botTitle
        resolvedBranding.logo = config.branding.logo ?? config.branding.avatar ?? bundle.branding.logo
        resolvedBranding.welcomeHeading = config.branding.welcomeTitle ?? bundle.branding.welcomeHeading
        resolvedBranding.disclaimerText = config.branding.welcomeSubtitle ?? bundle.branding.disclaimerText
        resolvedBranding.inputPlaceholder = config.branding.inputPlaceholder ?? bundle.branding.inputPlaceholder

        let resolvedTypography = config.branding.fontFamily.map { Chat360Typography(headFamily: $0, textFamily: $0) } ?? bundle.typography

        return content()
            .environment(\.chat360Colors, resolvedColors)
            .environment(\.chat360Typography, resolvedTypography)
            .environment(\.chat360Branding, resolvedBranding)
            .environment(\.chat360ThemeController, themeController)
            .environment(\.chat360UIConfig, config)
            .onAppear {
                if config.theme.defaultTheme == .system {
                    themeController.selectDarkTheme(colorScheme == .dark)
                }
            }
    }
}
