import SwiftUI

struct MultiChoiceContent: View {
    var message: ChatMessage
    var content: BotContent.MultiChoice
    var isLiveChat: Bool
    var onQuickReply: (BotContent.MultiChoice.Option) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PlainTextContent(text: message.text)
            ForEach(content.options, id: \.index) { option in
                QuickReplyButton(
                    text: option.text,
                    enabled: message.repliesEnabled && !isLiveChat,
                    selected: message.selectedReplyIndex == option.index,
                    onTap: { onQuickReply(option) }
                )
            }
        }
    }
}
