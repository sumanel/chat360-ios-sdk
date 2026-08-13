import SwiftUI

@available(iOS 15.0, *)
private let ratingEmojiSet = ["😞", "😕", "😐", "😊", "🤩"]

@available(iOS 15.0, *)
public struct RatingContent: View {
    @Environment(\.chat360Colors) private var colors

    private let message: ChatMessage
    private let content: BotContent.Rating
    private let isLiveChat: Bool
    private let onRatingSelected: (Int) -> Void

    public init(message: ChatMessage, content: BotContent.Rating, isLiveChat: Bool, onRatingSelected: @escaping (Int) -> Void) {
        self.message = message
        self.content = content
        self.isLiveChat = isLiveChat
        self.onRatingSelected = onRatingSelected
    }

    private var enabled: Bool { message.repliesEnabled && !isLiveChat }

    public var body: some View {
        HStack(spacing: 0) {
            if content.style == "star" {
                ForEach(0..<content.scale, id: \.self) { index in
                    let filled = message.selectedReplyIndex.map { index <= $0 } ?? false
                    Chat360Icon.star.image
                        .foregroundColor(filled ? colors.accent : colors.line)
                        .padding(.trailing, 4)
                        .onTapGesture { if enabled { onRatingSelected(index + 1) } }
                }
            } else {
                ForEach(Array(ratingEmojiSet.enumerated()), id: \.offset) { index, emoji in
                    let isSelected = message.selectedReplyIndex == index
                    Text(emoji)
                        .font(.system(size: isSelected ? 26 : 22))
                        .padding(.trailing, 6)
                        .onTapGesture { if enabled { onRatingSelected(index + 1) } }
                }
            }
        }
    }
}
