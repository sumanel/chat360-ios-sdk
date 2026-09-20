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
    public var welcomeLogoSize: CGFloat?

    public init(
        logo: Chat360Logo? = nil, botName: String? = nil, welcomeTitle: String? = nil, welcomeSubtitle: String? = nil,
        primaryColor: Color? = nil, secondaryColor: Color? = nil, avatar: Chat360Logo? = nil, fontFamily: Chat360FontFamily? = nil,
        inputPlaceholder: String? = nil, headerTitle: String? = nil, companyName: String? = nil, welcomeLogoSize: CGFloat? = nil
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
        self.welcomeLogoSize = welcomeLogoSize
    }
}

/// One button of the Assistant Mode switcher. `variables` are merged into the session-init `meta`
/// (the bot flow's `@`-variables) while this option is selected, e.g. `["agent_role": "trainer"]`.
/// Selecting a different option starts a new session so the new variables take effect.
@available(iOS 13.0, *)
public struct Chat360AssistantModeOption {
    public var label: String
    public var variables: [String: String]
    public var enabled: Bool

    public init(label: String, variables: [String: String] = [:], enabled: Bool = true) {
        self.label = label
        self.variables = variables
        self.enabled = enabled
    }
}

/// What to draw on a history row's chat bubble for a room's `agent_role`.
@available(iOS 13.0, *)
public struct Chat360AssistantRoleBadge: Equatable {
    /// The Assistant Mode button whose role this is (0 = training icon, else person icon); nil = no button sends it (generic tag icon).
    public let modeIndex: Int?
    /// The matched button's label, or the raw role text when nothing matches.
    public let label: String

    public init(modeIndex: Int?, label: String) {
        self.modeIndex = modeIndex
        self.label = label
    }
}

@available(iOS 13.0, *)
extension Array where Element == Chat360AssistantModeOption {
    /// The index of the option whose `agent_role` variable equals `role`, ignoring case and surrounding spaces.
    public func indexForRole(_ role: String?) -> Int? {
        guard let wanted = role?.trimmingCharacters(in: .whitespacesAndNewlines), !wanted.isEmpty else { return nil }
        return firstIndex {
            $0.variables[Chat360FeatureConfig.assistantRoleKey]?.trimmingCharacters(in: .whitespacesAndNewlines)
                .caseInsensitiveCompare(wanted) == .orderedSame
        }
    }

    /// The badge for a room's `role`: its button when one sends it, a generic one when none does, and nil when the room has no role.
    public func badge(forRole role: String?) -> Chat360AssistantRoleBadge? {
        guard let trimmed = role?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        let index = indexForRole(trimmed)
        return Chat360AssistantRoleBadge(modeIndex: index, label: index.map { self[$0].label } ?? trimmed)
    }
}

@available(iOS 13.0, *)
public struct Chat360FeatureConfig {
    public var showMenu: Bool = false
    public var showHistorySidebar: Bool = true
    public var showNewChat: Bool = false
    public var showFeedback: Bool = true
    public var showCopyMessage: Bool = true
    public var showRegenerate: Bool = false
    public var showLike: Bool = true
    public var showDislike: Bool = true
    public var showEmoji: Bool = false
    public var showAttachment: Bool = false
    public var showVoiceInput: Bool = true
    public var showSpeechToText: Bool
    public var showCamera: Bool = true
    public var showSend: Bool = true
    public var showAssistantMode: Bool = true
    /// The Assistant Mode buttons, in display order - at most `maxAssistantModes` (2); any extra are ignored.
    /// The first uses the training icon, the second the person icon.
    public var assistantModes: [Chat360AssistantModeOption] = [
        Chat360AssistantModeOption(label: "Training"),
        Chat360AssistantModeOption(label: "Customer"),
    ]
    /// Index into `assistantModes` selected when the chat opens.
    public var defaultAssistantMode: Int = 1
    public var showAppearanceSwitcher: Bool = false
    public var showTypingIndicator: Bool = true
    public var enableVoicePreview: Bool = false
    public var showBotAvatar: Bool = true
    // Defaults true: ChatController presents fullScreen, which doesn't support swipe-to-dismiss,
    // so a host that turns this off must provide its own way to close the chat screen.
    public var showClose: Bool = true
    // The mandatory "how's it going so far?" prompt that fires every random N live bot replies,
    // N drawn from `periodicFeedbackPromptInterval` below (see
    // `ChatViewModel.registerLiveBotReplyForFeedbackPrompt`) - separate from `showFeedback`
    // above, which is the end-of-conversation rating dialog.
    public var showPeriodicFeedbackPrompt: Bool = true
    // How many live bot replies elapse between periodic feedback prompts, re-rolled within this
    // range each time. Widened from the original 3...5 (which read as "every 3-4 chats") to a
    // less intrusive default; clients can override to tune frequency without an SDK code change.
    public var periodicFeedbackPromptInterval: ClosedRange<Int> = 8...12

    public init(
        showMenu: Bool = false, showHistorySidebar: Bool = true, showNewChat: Bool = false, showFeedback: Bool = true,
        showCopyMessage: Bool = true, showRegenerate: Bool = false, showLike: Bool = true, showDislike: Bool = true,
        showEmoji: Bool = false, showAttachment: Bool = false, showVoiceInput: Bool = true, showSpeechToText: Bool? = nil,
        showCamera: Bool = true, showSend: Bool = true, showAssistantMode: Bool = true, showAppearanceSwitcher: Bool = false,
        showTypingIndicator: Bool = true, enableVoicePreview: Bool = false, showBotAvatar: Bool = true, showClose: Bool = true,
        showPeriodicFeedbackPrompt: Bool = true, periodicFeedbackPromptInterval: ClosedRange<Int> = 8...12,
        assistantModes: [Chat360AssistantModeOption]? = nil, defaultAssistantMode: Int = 1
    ) {
        self.showMenu = showMenu
        self.showHistorySidebar = showHistorySidebar
        self.showNewChat = showNewChat
        self.showFeedback = showFeedback
        self.showCopyMessage = showCopyMessage
        self.showRegenerate = showRegenerate
        self.showLike = showLike
        self.showDislike = showDislike
        self.showPeriodicFeedbackPrompt = showPeriodicFeedbackPrompt
        self.periodicFeedbackPromptInterval = periodicFeedbackPromptInterval
        self.showEmoji = showEmoji
        self.showAttachment = showAttachment
        self.showVoiceInput = showVoiceInput
        self.showSpeechToText = showSpeechToText ?? showVoiceInput
        self.showCamera = showCamera
        self.showSend = showSend
        self.showAssistantMode = showAssistantMode
        if let assistantModes { self.assistantModes = assistantModes }
        self.defaultAssistantMode = defaultAssistantMode
        self.showAppearanceSwitcher = showAppearanceSwitcher
        self.showTypingIndicator = showTypingIndicator
        self.enableVoicePreview = enableVoicePreview
        self.showBotAvatar = showBotAvatar
        self.showClose = showClose
    }

    /// The Assistant Mode switcher has room for two buttons.
    public static let maxAssistantModes = 2

    /// `assistantModes` capped at `maxAssistantModes`.
    public var effectiveAssistantModes: [Chat360AssistantModeOption] {
        Array(assistantModes.prefix(Self.maxAssistantModes))
    }

    /// The variable name that carries the role in session-init `meta` and comes back on `rooms/list`.
    public static let assistantRoleKey = "agent_role"

    /// The index of the button whose variables carry `role` as `agent_role` (ignoring case and surrounding spaces), or nil when none does.
    public func assistantModeIndex(forRole role: String?) -> Int? {
        effectiveAssistantModes.indexForRole(role)
    }

    /// The selected option at chat open, clamped into range of the (capped) options.
    public var initialAssistantModeIndex: Int {
        min(max(defaultAssistantMode, 0), max(effectiveAssistantModes.count - 1, 0))
    }

    /// Variables to seed session-init `meta` with at chat open; empty when the switcher is hidden.
    public var initialAssistantVariables: [String: String] {
        guard showAssistantMode, effectiveAssistantModes.indices.contains(initialAssistantModeIndex) else { return [:] }
        return effectiveAssistantModes[initialAssistantModeIndex].variables
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
