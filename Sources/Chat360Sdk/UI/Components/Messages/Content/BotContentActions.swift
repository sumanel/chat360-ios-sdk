import Foundation

/// All user-interaction callbacks a bot content renderer might need, bundled so adding a new
/// content type's interaction means adding one field here with a default - never touching every
/// call site's parameter list.
struct BotContentActions {
    var onQuickReply: (BotContent.MultiChoice.Option) -> Void = { _ in }
    var onAttachmentClick: () -> Void = {}
    var onCameraClick: () -> Void = {}
    var onRatingSelected: (Int) -> Void = { _ in }
    var onFormFieldChange: (_ fieldIndex: Int, _ value: String) -> Void = { _, _ in }
    var onMediaFieldPicked: (_ fieldIndex: Int, _ bytes: Data, _ fileName: String, _ mimeType: String) -> Void = { _, _, _, _ in }
    /// Triggers whatever picker UI should run for a FORM MEDIA field at `fieldIndex`; the picker
    /// itself calls `onMediaFieldPicked` once it resolves. Wired to a real picker in Phase 7.
    var onPickMediaField: (_ fieldIndex: Int) -> Void = { _ in }
    var onFormSubmit: () -> Void = {}
    /// Shared by EmailPrompt (value only) and PhonePrompt (country code + national number).
    var onPromptValueChange: (_ primary: String, _ secondary: String) -> Void = { _, _ in }
    var onEmailSubmit: () -> Void = {}
    var onPhoneSubmit: () -> Void = {}
    var onAutoSuggestionSelected: (_ index: Int, _ text: String) -> Void = { _, _ in }
    var onDateSelected: (_ formattedDate: String) -> Void = { _ in }
    var onTimeSubmit: (_ formattedTime: String) -> Void = { _ in }
    var onCheckboxToggle: (Int) -> Void = { _ in }
    var onCheckboxSubmit: () -> Void = {}
    var onImageButtonClick: (BotContent.ImageButtons.Card, BotContent.ImageButtons.Button) -> Void = { _, _ in }
    var onTextCarouselTap: (_ text: String, _ clickedIndex: Int, _ targetId: String?) -> Void = { _, _, _ in }
    var onWelcomeCardSelected: (BotContent.WelcomeScreen.Card, Int) -> Void = { _, _ in }
    var onIframeAdvance: (_ targetId: String) -> Void = { _ in }
    var onCopy: () -> Void = {}
    var onRegenerate: () -> Void = {}
    var onLike: () -> Void = {}
    var onDislike: () -> Void = {}
}
