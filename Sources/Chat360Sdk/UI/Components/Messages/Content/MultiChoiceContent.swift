import SwiftUI

@available(iOS 16.0, *)
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
        VStack(alignment: .leading, spacing: 10) {
            PlainTextContent(message.text)
            FlowLayout(spacing: 8) {
                ForEach(content.options, id: \.index) { option in
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
}
