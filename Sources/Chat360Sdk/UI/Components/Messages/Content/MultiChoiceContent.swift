import SwiftUI

@available(iOS 15.0, *)
public struct MultiChoiceContent: View {
    private let message: ChatMessage
    private let content: BotContent.MultiChoice
    private let isLiveChat: Bool
    private let onQuickReply: (BotContent.MultiChoice.Option) -> Void

    public init(message: ChatMessage, content: BotContent.MultiChoice, isLiveChat: Bool, onQuickReply: @escaping (BotContent.MultiChoice.Option) -> Void) {
        self.message = message
        self.content = content
        self.isLiveChat = isLiveChat
        self.onQuickReply = onQuickReply
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PlainTextContent(message.text)
            ForEach(content.options, id: \.index) { option in
                Spacer().frame(height: 10)
                QuickReplyButton(
                    text: option.text,
                    enabled: message.repliesEnabled && !isLiveChat,
                    selected: message.selectedReplyIndex == option.index,
                    onClick: { onQuickReply(option) }
                )
            }
        }
    }
}
