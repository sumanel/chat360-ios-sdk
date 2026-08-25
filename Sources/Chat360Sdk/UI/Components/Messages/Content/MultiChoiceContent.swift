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

    // Bot-authored copy sometimes ends in trailing blank lines (`<br><br>`) meant to put daylight
    // between the question and the old full-width buttons - with the links now sitting much
    // closer to the text, that trailing whitespace just reads as a big empty gap, so it's trimmed
    // rather than rendered.
    private var trimmedText: String {
        message.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PlainTextContent(trimmedText)
            if !content.options.isEmpty {
                Spacer().frame(height: 6)
                // Nudges render as comma-separated underlined links (via `FlowLayout`, which needs
                // iOS 16's Layout protocol) rather than stacked buttons - MultiChoiceContent itself
                // stays at iOS 15 for everything else it does, so this is gated locally instead of
                // bumping the whole type's availability just for this.
                if #available(iOS 16.0, *) {
                    FlowLayout(spacing: 4) {
                        ForEach(Array(content.options.enumerated()), id: \.element.index) { index, option in
                            QuickReplyLink(
                                text: linkText(for: option, isLast: index == content.options.count - 1),
                                enabled: message.repliesEnabled && !isLiveChat,
                                selected: message.selectedReplyIndex == option.index,
                                onClick: { onQuickReply(option) }
                            )
                        }
                    }
                } else {
                    ForEach(content.options, id: \.index) { option in
                        QuickReplyLink(
                            text: option.text,
                            enabled: message.repliesEnabled && !isLiveChat,
                            selected: message.selectedReplyIndex == option.index,
                            onClick: { onQuickReply(option) }
                        )
                        Spacer().frame(height: 4)
                    }
                }
            }
        }
    }

    private func linkText(for option: BotContent.MultiChoice.Option, isLast: Bool) -> String {
        isLast ? option.text : "\(option.text),"
    }
}
