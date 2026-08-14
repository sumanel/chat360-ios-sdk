import SwiftUI

@available(iOS 13.0, *)
public enum Chat360DefaultTheme: Equatable {
    case light, dark, system
}

@available(iOS 13.0, *)
public struct Chat360ThemeConfig: Equatable {
    public var defaultTheme: Chat360DefaultTheme = .system
    public var allowThemeSwitch: Bool = false
    public var followSystemTheme: Bool = true

    public init(defaultTheme: Chat360DefaultTheme = .system, allowThemeSwitch: Bool = false, followSystemTheme: Bool = true) {
        self.defaultTheme = defaultTheme
        self.allowThemeSwitch = allowThemeSwitch
        self.followSystemTheme = followSystemTheme
    }
}

@available(iOS 13.0, *)
public struct Chat360BrandingConfig {
    public var logo: Chat360Logo?
    public var botName: String?
    public var welcomeTitle: String?
    public var welcomeSubtitle: String?
    public var primaryColor: Color?
    public var secondaryColor: Color?
    public var avatar: Chat360Logo?
    public var fontFamily: Chat360FontFamily?
    public var inputPlaceholder: String?
    public var headerTitle: String?
    public var companyName: String?

    public init(
        logo: Chat360Logo? = nil, botName: String? = nil, welcomeTitle: String? = nil, welcomeSubtitle: String? = nil,
        primaryColor: Color? = nil, secondaryColor: Color? = nil, avatar: Chat360Logo? = nil, fontFamily: Chat360FontFamily? = nil,
        inputPlaceholder: String? = nil, headerTitle: String? = nil, companyName: String? = nil
    ) {
        self.logo = logo
        self.botName = botName
        self.welcomeTitle = welcomeTitle
        self.welcomeSubtitle = welcomeSubtitle
        self.primaryColor = primaryColor
        self.secondaryColor = secondaryColor
        self.avatar = avatar
        self.fontFamily = fontFamily
        self.inputPlaceholder = inputPlaceholder
        self.headerTitle = headerTitle
        self.companyName = companyName
    }
}

@available(iOS 13.0, *)
public struct Chat360FeatureConfig {
    public var showMenu: Bool = false
    public var showHistorySidebar: Bool = true
    public var showNewChat: Bool = false
    public var showFeedback: Bool = true
    public var showCopyMessage: Bool = true
    public var showRegenerate: Bool = true
    public var showLike: Bool = true
    public var showDislike: Bool = true
    public var showEmoji: Bool = false
    public var showAttachment: Bool = false
    public var showVoiceInput: Bool = true
    public var showSpeechToText: Bool
    public var showCamera: Bool = true
    public var showSend: Bool = true
    public var showAssistantMode: Bool = true
    public var showAppearanceSwitcher: Bool = false
    public var showTypingIndicator: Bool = true
    public var enableVoicePreview: Bool = false
    public var showBotAvatar: Bool = true

    public init(
        showMenu: Bool = false, showHistorySidebar: Bool = true, showNewChat: Bool = false, showFeedback: Bool = true,
        showCopyMessage: Bool = true, showRegenerate: Bool = true, showLike: Bool = true, showDislike: Bool = true,
        showEmoji: Bool = false, showAttachment: Bool = false, showVoiceInput: Bool = true, showSpeechToText: Bool? = nil,
        showCamera: Bool = true, showSend: Bool = true, showAssistantMode: Bool = true, showAppearanceSwitcher: Bool = false,
        showTypingIndicator: Bool = true, enableVoicePreview: Bool = false, showBotAvatar: Bool = true
    ) {
        self.showMenu = showMenu
        self.showHistorySidebar = showHistorySidebar
        self.showNewChat = showNewChat
        self.showFeedback = showFeedback
        self.showCopyMessage = showCopyMessage
        self.showRegenerate = showRegenerate
        self.showLike = showLike
        self.showDislike = showDislike
        self.showEmoji = showEmoji
        self.showAttachment = showAttachment
        self.showVoiceInput = showVoiceInput
        self.showSpeechToText = showSpeechToText ?? showVoiceInput
        self.showCamera = showCamera
        self.showSend = showSend
        self.showAssistantMode = showAssistantMode
        self.showAppearanceSwitcher = showAppearanceSwitcher
        self.showTypingIndicator = showTypingIndicator
        self.enableVoicePreview = enableVoicePreview
        self.showBotAvatar = showBotAvatar
    }
}

@available(iOS 13.0, *)
public struct Chat360BehaviorConfig {
    public var suppressInitialBotMessages: Bool = false

    public init(suppressInitialBotMessages: Bool = false) {
        self.suppressInitialBotMessages = suppressInitialBotMessages
    }
}

@available(iOS 13.0, *)
public struct Chat360UIConfigSlots {
    public var header: (() -> AnyView)?
    public var footer: (() -> AnyView)?
    public var messageToolbar: (() -> AnyView)?
    public var welcomeScreen: (() -> AnyView)?

    public init(
        header: (() -> AnyView)? = nil, footer: (() -> AnyView)? = nil,
        messageToolbar: (() -> AnyView)? = nil, welcomeScreen: (() -> AnyView)? = nil
    ) {
        self.header = header
        self.footer = footer
        self.messageToolbar = messageToolbar
        self.welcomeScreen = welcomeScreen
    }
}

@available(iOS 13.0, *)
public struct Chat360Callbacks {
    public var onMenuClicked: () -> Void = {}
    public var onNewChatClicked: () -> Void = {}
    public var onCopyClicked: (String, String) -> Void = { _, _ in }
    public var onRegenerateClicked: (String) -> Void = { _ in }
    public var onFeedback: (String, Bool) -> Void = { _, _ in }
    public var onHistorySelected: (String) -> Void = { _ in }

    public init(
        onMenuClicked: @escaping () -> Void = {}, onNewChatClicked: @escaping () -> Void = {},
        onCopyClicked: @escaping (String, String) -> Void = { _, _ in }, onRegenerateClicked: @escaping (String) -> Void = { _ in },
        onFeedback: @escaping (String, Bool) -> Void = { _, _ in }, onHistorySelected: @escaping (String) -> Void = { _ in }
    ) {
        self.onMenuClicked = onMenuClicked
        self.onNewChatClicked = onNewChatClicked
        self.onCopyClicked = onCopyClicked
        self.onRegenerateClicked = onRegenerateClicked
        self.onFeedback = onFeedback
        self.onHistorySelected = onHistorySelected
    }
}

@available(iOS 13.0, *)
public struct Chat360UIConfig {
    public var branding: Chat360BrandingConfig
    public var theme: Chat360ThemeConfig
    public var features: Chat360FeatureConfig
    public var behavior: Chat360BehaviorConfig
    public var ui: Chat360UIConfigSlots
    public var callbacks: Chat360Callbacks

    public init(
        branding: Chat360BrandingConfig = Chat360BrandingConfig(),
        theme: Chat360ThemeConfig = Chat360ThemeConfig(),
        features: Chat360FeatureConfig = Chat360FeatureConfig(),
        behavior: Chat360BehaviorConfig = Chat360BehaviorConfig(),
        ui: Chat360UIConfigSlots = Chat360UIConfigSlots(),
        callbacks: Chat360Callbacks = Chat360Callbacks()
    ) {
        self.branding = branding
        self.theme = theme
        self.features = features
        self.behavior = behavior
        self.ui = ui
        self.callbacks = callbacks
    }
}

@available(iOS 13.0, *)
public struct Chat360UIConfigKey: EnvironmentKey {
    public static let defaultValue = Chat360UIConfig()
}

@available(iOS 13.0, *)
extension EnvironmentValues {
    public var chat360UIConfig: Chat360UIConfig {
        get { self[Chat360UIConfigKey.self] }
        set { self[Chat360UIConfigKey.self] = newValue }
    }
}
