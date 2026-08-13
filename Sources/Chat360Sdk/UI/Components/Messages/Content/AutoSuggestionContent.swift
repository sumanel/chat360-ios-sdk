import SwiftUI

@available(iOS 15.0, *)
public struct AutoSuggestionContent: View {
    @Environment(\.chat360Colors) private var colors
    @Environment(\.chat360Typography) private var typography

    private let message: ChatMessage
    private let content: BotContent.AutoSuggestion
    private let isLiveChat: Bool
    private let onSelected: (Int, String) -> Void

    public init(message: ChatMessage, content: BotContent.AutoSuggestion, isLiveChat: Bool, onSelected: @escaping (Int, String) -> Void) {
        self.message = message
        self.content = content
        self.isLiveChat = isLiveChat
        self.onSelected = onSelected
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PlainTextContent(message.text)
            if let description = content.description {
                Spacer().frame(height: 6)
                Text(description)
                    .font(typography.textFamily.font(size: 13))
                    .foregroundColor(colors.textSecondary)
            }
            ForEach(Array(content.choices.enumerated()), id: \.offset) { index, choice in
                Spacer().frame(height: 10)
                QuickReplyButton(
                    text: choice,
                    enabled: message.repliesEnabled && !isLiveChat,
                    selected: message.selectedReplyIndex == index,
                    onClick: { onSelected(index, choice) }
                )
            }
        }
    }
}
