import SwiftUI

/// Renders the AUTOSUGGESTION sub-case of CUSTOMINPUT as a plain choice list: a single tap both
/// selects and submits, matching how MULTI_CHOICE already behaves natively.
struct AutoSuggestionContent: View {
    var message: ChatMessage
    var content: BotContent.AutoSuggestion
    var isLiveChat: Bool
    var onSelected: (_ index: Int, _ text: String) -> Void

    @Environment(\.chat360Colors) private var colors
    @Environment(\.chat360Typography) private var typography

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PlainTextContent(text: message.text)
            if let description = content.description {
                Text(description).font(textFont(size: 13)).foregroundColor(colors.textSecondary)
            }
            ForEach(Array(content.choices.enumerated()), id: \.offset) { index, choice in
                QuickReplyButton(
                    text: choice,
                    enabled: message.repliesEnabled && !isLiveChat,
                    selected: message.selectedReplyIndex == index,
                    onTap: { onSelected(index, choice) }
                )
            }
        }
    }

    private func textFont(size: CGFloat) -> Font {
        if let name = typography.textFontName { return .custom(name, size: size) }
        return .system(size: size)
    }
}
