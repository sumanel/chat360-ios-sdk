import Foundation

@available(iOS 13.0, *)
public struct BotContentActions {
    public var onQuickReply: (BotContent.MultiChoice.Option) -> Void = { _ in }
    public var onAttachmentClick: () -> Void = {}
    public var onCameraClick: () -> Void = {}
    public var onRatingSelected: (Int) -> Void = { _ in }
    public var onFormFieldChange: (Int, String) -> Void = { _, _ in }
    public var onMediaFieldPicked: (Int, Data, String, String) -> Void = { _, _, _, _ in }
    public var onFormSubmit: () -> Void = {}
    public var onPromptValueChange: (String, String) -> Void = { _, _ in }
    public var onEmailSubmit: () -> Void = {}
    public var onPhoneSubmit: () -> Void = {}
    public var onAutoSuggestionSelected: (Int, String) -> Void = { _, _ in }
    public var onDateSelected: (String) -> Void = { _ in }
    public var onTimeSubmit: (String) -> Void = { _ in }
    public var onCheckboxToggle: (Int) -> Void = { _ in }
    public var onCheckboxSubmit: () -> Void = {}
    public var onImageButtonClick: (BotContent.ImageButtons.Card, BotContent.ImageButtons.Button) -> Void = { _, _ in }
    public var onTextCarouselTap: (String, Int, String?) -> Void = { _, _, _ in }
    public var onWelcomeCardSelected: (BotContent.WelcomeScreen.Card, Int) -> Void = { _, _ in }
    public var onIframeAdvance: (String) -> Void = { _ in }
    public var onRegenerateClicked: () -> Void = {}
    public var onLikeClicked: () -> Void = {}
    public var onDislikeClicked: () -> Void = {}

    public init() {}
}
