import Foundation

/// Which affordances the input bar shows, independent of theme preset - a host app can keep the
/// default full bar or turn any of these off (e.g. Hyundai's build hides attachment/emoji) without
/// forking `ChatInputBar` itself. Swift-only (not `@objc`), same as `Chat360Typography`/`Chat360Branding`.
public struct Chat360InputBarConfig: Equatable {
    public var showAttachment: Bool
    public var showEmoji: Bool
    /// Speech-to-text dictation (fills the text field). Still requires platform/permission support
    /// at runtime regardless of this flag - this only controls whether the *option* is offered.
    public var showDictation: Bool
    /// Voice message recording.
    public var showMic: Bool
    public var inputPlaceholder: String

    public init(
        showAttachment: Bool = true,
        showEmoji: Bool = true,
        showDictation: Bool = true,
        showMic: Bool = true,
        inputPlaceholder: String = "Type a message…"
    ) {
        self.showAttachment = showAttachment
        self.showEmoji = showEmoji
        self.showDictation = showDictation
        self.showMic = showMic
        self.inputPlaceholder = inputPlaceholder
    }
}

/// The library's own default: every affordance on.
public let DefaultInputBarConfig = Chat360InputBarConfig()
