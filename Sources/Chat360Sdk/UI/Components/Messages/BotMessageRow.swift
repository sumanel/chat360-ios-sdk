import SwiftUI

/// Row chrome (avatar, name label, card, timestamp) shared by every bot content type. When
/// `message` is agent-authored and `assignedAgent` is known, the name/avatar swap to the human
/// agent's instead of the bot's - adapted to per-message since this app has no persistent header
/// identity to swap instead.
struct BotMessageRow: View {
    var message: ChatMessage
    var actions: BotContentActions
    var isLiveChat: Bool = false
    var assignedAgent: AssignedAgent?

    @Environment(\.chat360Colors) private var colors
    @Environment(\.chat360Typography) private var typography
    @Environment(\.chat360Branding) private var branding

    private var agent: AssignedAgent? {
        message.author == .agent ? assignedAgent : nil
    }

    private var displayName: String {
        agent?.name?.trimmingCharacters(in: .whitespaces).nilIfEmpty ?? branding.botTitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 8) {
                LogoBadge(size: 28, overrideName: agent?.name, overrideAvatarUrl: agent?.avatarUrl)
                Text(displayName)
                    .font(textFont(size: 13))
                    .fontWeight(.medium)
                    .foregroundColor(colors.textSecondary)
            }
            Spacer().frame(height: 6)
            VStack(alignment: .leading, spacing: 0) {
                BotContentBody(message: message, actions: actions, isLiveChat: isLiveChat)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(colors.bubbleAiBackground)
            .overlay(RoundedRectangle(cornerRadius: 2).stroke(colors.cardBorder, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 2))
            Spacer().frame(height: 4)
            Text(message.timeText)
                .font(textFont(size: 11))
                .foregroundColor(colors.textDisabled)
            if !isLiveChat {
                Spacer().frame(height: 6)
                MessageActionsRow(
                    feedback: message.feedback,
                    onCopy: actions.onCopy,
                    onRegenerate: actions.onRegenerate,
                    onLike: actions.onLike,
                    onDislike: actions.onDislike
                )
            }
        }
    }

    private func textFont(size: CGFloat) -> Font {
        if let name = typography.textFontName { return .custom(name, size: size) }
        return .system(size: size)
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
