import SwiftUI

/// Dispatches a bot message's `BotContent` to its renderer. Adding a new content type is: a new
/// `BotContent` case (Model/Wire), a new View in this folder, and one branch here - never a
/// change to `ChatMessage` or the row chrome around this.
struct BotContentBody: View {
    var message: ChatMessage
    var actions: BotContentActions
    var isLiveChat: Bool = false

    var body: some View {
        switch message.content {
        case .multiChoice(let content):
            MultiChoiceContent(message: message, content: content, isLiveChat: isLiveChat, onQuickReply: actions.onQuickReply)
        case .media(let content):
            MediaContent(message: message, content: content, isLiveChat: isLiveChat, onDynamicButtonClick: actions.onTextCarouselTap)
        case .carousel(let content):
            CarouselContent(caption: message.text, content: content)
        case .fileUploadPrompt(let content):
            FileUploadPromptContent(content: content, isLiveChat: isLiveChat, onAttachmentClick: actions.onAttachmentClick, onCameraClick: actions.onCameraClick)
        case .downloadMedia(let content):
            DownloadMediaContent(content: content)
        case .rating(let content):
            RatingContent(message: message, content: content, isLiveChat: isLiveChat, onRatingSelected: actions.onRatingSelected)
        case .form(let content):
            FormContent(message: message, content: content, isLiveChat: isLiveChat, onFieldChange: actions.onFormFieldChange, onPickMediaField: actions.onPickMediaField, onSubmit: actions.onFormSubmit)
        // Never actually reaches the message list (the view model skips WINDOW_EVENT nodes
        // entirely) - kept only so this `switch` stays exhaustive as BotContent grows.
        case .windowEvent:
            EmptyView()
        case .emailPrompt:
            EmailPromptContent(message: message, isLiveChat: isLiveChat, onValueChange: actions.onPromptValueChange, onSubmit: actions.onEmailSubmit)
        // A non-international PhonePrompt has no dedicated widget in the source either - the
        // always-visible bottom input bar already answers it as free text.
        case .phonePrompt(let content):
            if content.allowInternational {
                PhonePromptContent(message: message, content: content, isLiveChat: isLiveChat, onValueChange: actions.onPromptValueChange, onSubmit: actions.onPhoneSubmit)
            } else {
                PlainTextContent(text: message.text)
            }
        case .autoSuggestion(let content):
            AutoSuggestionContent(message: message, content: content, isLiveChat: isLiveChat, onSelected: actions.onAutoSuggestionSelected)
        case .datePrompt(let content):
            DatePromptContent(message: message, content: content, isLiveChat: isLiveChat, onDateSelected: actions.onDateSelected)
        case .timePrompt(let content):
            TimePromptContent(message: message, content: content, isLiveChat: isLiveChat, onSubmit: actions.onTimeSubmit)
        case .multiOption(let content):
            MultiOptionContent(message: message, content: content, isLiveChat: isLiveChat, onToggle: actions.onCheckboxToggle, onSubmit: actions.onCheckboxSubmit)
        case .imageButtons(let content):
            ImageButtonsContent(message: message, content: content, isLiveChat: isLiveChat, onButtonClick: actions.onImageButtonClick)
        case .textCarousel(let content):
            TextCarouselContent(message: message, content: content, isLiveChat: isLiveChat, onCardTap: actions.onTextCarouselTap)
        case .linkCard(let content):
            LinkCardContent(caption: message.text, content: content)
        case .agentTransferNotice:
            AgentTransferNoticeContent(text: message.text)
        case .welcomeScreen(let content):
            WelcomeScreenContent(message: message, content: content, isLiveChat: isLiveChat, onCardSelected: actions.onWelcomeCardSelected)
        case .iframeContent(let content):
            IframeContent(content: content, onAdvance: actions.onIframeAdvance)
        case .plainText:
            PlainTextContent(text: message.text)
        case .unsupported:
            UnsupportedContent(text: message.text, content: message.content)
        }
    }
}
