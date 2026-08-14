import SwiftUI

@available(iOS 16.0, *)
public struct BotContentBody: View {
    private let message: ChatMessage
    private let actions: BotContentActions
    private let isLiveChat: Bool

    public init(message: ChatMessage, actions: BotContentActions, isLiveChat: Bool = false) {
        self.message = message
        self.actions = actions
        self.isLiveChat = isLiveChat
    }

    public var body: some View {
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
            FormContent(message: message, content: content, isLiveChat: isLiveChat, onFieldChange: actions.onFormFieldChange, onMediaFieldPicked: actions.onMediaFieldPicked, onSubmit: actions.onFormSubmit)
        case .windowEvent:
            EmptyView()
        case .emailPrompt:
            EmailPromptContent(message: message, isLiveChat: isLiveChat, onValueChange: actions.onPromptValueChange, onSubmit: actions.onEmailSubmit)
        case .phonePrompt(let content):
            if content.allowInternational {
                PhonePromptContent(message: message, content: content, isLiveChat: isLiveChat, onValueChange: actions.onPromptValueChange, onSubmit: actions.onPhoneSubmit)
            } else {
                PlainTextContent(message.text)
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
            PlainTextContent(message.text)
        case .unsupported(let content):
            UnsupportedContent(text: message.text, content: content)
        }
    }
}

@available(iOS 16.0, *)
extension ChatMessage {
    public func copyText() -> String {
        switch content {
        case .multiChoice(let content):
            var result = text.toPlainText()
            for option in content.options {
                result += "\n" + option.text
            }
            return result
        case .multiOption(let content):
            var result = ""
            if let description = content.description { result += description }
            for option in content.options {
                if !result.isEmpty { result += "\n" }
                result += option.text
            }
            return result
        default:
            return text.toPlainText()
        }
    }
}
