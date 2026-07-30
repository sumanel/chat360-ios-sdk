import SwiftUI

private let ratingEmojiSet = ["😞", "😕", "😐", "😊", "🤩"]

/// A row of stars, or a row of 5 fixed emoji, each index sends (i+1).
struct RatingContent: View {
    var message: ChatMessage
    var content: BotContent.Rating
    var isLiveChat: Bool
    var onRatingSelected: (Int) -> Void

    @Environment(\.chat360Colors) private var colors

    private var enabled: Bool { message.repliesEnabled && !isLiveChat }
    private var selected: Int? { message.selectedReplyIndex }

    var body: some View {
        HStack(spacing: content.style == "star" ? 4 : 6) {
            if content.style == "star" {
                ForEach(0..<content.scale, id: \.self) { index in
                    let filled = selected != nil && index <= selected!
                    Button(action: { onRatingSelected(index + 1) }) {
                        Image(systemName: filled ? "star.fill" : "star")
                            .foregroundColor(filled ? colors.accent : colors.line)
                    }
                    .disabled(!enabled)
                    .buttonStyle(.plain)
                }
            } else {
                ForEach(Array(ratingEmojiSet.enumerated()), id: \.offset) { index, emoji in
                    let isSelected = selected == index
                    Button(action: { onRatingSelected(index + 1) }) {
                        Text(emoji).font(.system(size: isSelected ? 26 : 22))
                    }
                    .disabled(!enabled)
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
