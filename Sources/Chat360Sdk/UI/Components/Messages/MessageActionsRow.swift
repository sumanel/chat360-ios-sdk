import SwiftUI

/// Copy / regenerate / like / dislike row under a bot message bubble.
struct MessageActionsRow: View {
    var feedback: MessageFeedback?
    var onCopy: () -> Void
    var onRegenerate: () -> Void
    var onLike: () -> Void
    var onDislike: () -> Void

    @Environment(\.chat360Colors) private var colors
    @State private var showCopied = false

    var body: some View {
        HStack(spacing: 16) {
            Button(action: copyTapped) {
                icon(showCopied ? "checkmark" : "doc.on.doc", active: showCopied)
            }
            .buttonStyle(.plain)

            Button(action: onRegenerate) {
                icon("arrow.counterclockwise", active: false)
            }
            .buttonStyle(.plain)

            Button(action: onLike) {
                icon(feedback == .like ? "hand.thumbsup.fill" : "hand.thumbsup", active: feedback == .like)
            }
            .buttonStyle(.plain)

            Button(action: onDislike) {
                icon(feedback == .dislike ? "hand.thumbsdown.fill" : "hand.thumbsdown", active: feedback == .dislike)
            }
            .buttonStyle(.plain)
        }
    }

    private func copyTapped() {
        onCopy()
        showCopied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { showCopied = false }
    }

    private func icon(_ systemName: String, active: Bool) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 13))
            .foregroundColor(active ? colors.accent : colors.textSecondary)
            .frame(width: 22, height: 22)
    }
}
