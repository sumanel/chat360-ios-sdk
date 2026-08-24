import SwiftUI

@available(iOS 16.0, *)
public struct BotMessageRow: View {
    @Environment(\.chat360Colors) private var colors
    @Environment(\.chat360Typography) private var typography
    @Environment(\.chat360UIConfig) private var config

    private let message: ChatMessage
    private let actions: BotContentActions
    private let isLiveChat: Bool
    private let assignedAgent: AssignedAgent?
    // `messageReactions` loads from local cache asynchronously, separately from the message
    // replay itself, so this is almost always still nil the first time this row mounts after an
    // app restart. `@State`'s init-time seeding only runs once per view identity, so the
    // `onChange` below is what actually picks up the persisted value once it arrives.
    private let initialReaction: Bool?
    // Regenerate re-sends the query and waits for a fresh bot reply, same as any other message -
    // while one is already in flight, tapping it again queues up a second one on top, which is
    // what let it be tapped repeatedly. Disabled for every row while the bot is responding, not
    // just the one being regenerated, matching how the input bar's send button already behaves.
    private let isAgentTyping: Bool

    @State private var feedback: Bool?
    @State private var justCopied = false

    public init(message: ChatMessage, actions: BotContentActions, isLiveChat: Bool = false, assignedAgent: AssignedAgent? = nil, initialReaction: Bool? = nil, isAgentTyping: Bool = false) {
        self.message = message
        self.actions = actions
        self.isLiveChat = isLiveChat
        self.assignedAgent = assignedAgent
        self.initialReaction = initialReaction
        self.isAgentTyping = isAgentTyping
        self._feedback = State(initialValue: initialReaction)
    }

    private var agent: AssignedAgent? {
        message.author == .agent ? assignedAgent : nil
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if config.features.showBotAvatar {
                LogoBadge(size: 28, overrideName: agent?.name, overrideAvatarUrl: agent?.avatarUrl)
                Spacer().frame(height: 6)
            }
            VStack(alignment: .leading, spacing: 0) {
                BotContentBody(message: message, actions: actions, isLiveChat: isLiveChat)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(colors.bubbleAiBackground)
            .overlay(Rectangle().stroke(colors.cardBorder, lineWidth: 1))

            Spacer().frame(height: 4)
            HStack(spacing: 18) {
                Text(message.timeText)
                    .font(typography.textFamily.font(size: 11, weight: .semibold))
                    .foregroundColor(colors.textDisabled)
                if config.features.showCopyMessage {
                    (justCopied ? Chat360Icon.check.image : Chat360Icon.copy.image)
                        .foregroundColor(justCopied ? colors.accent : colors.textSecondary)
                        .frame(width: 18, height: 18)
                        .onTapGesture {
                            UIPasteboard.general.string = message.copyText()
                            justCopied = true
                            Task {
                                try? await Task.sleep(nanoseconds: 1_000_000_000)
                                justCopied = false
                            }
                        }
                }
                if config.features.showRegenerate {
                    Chat360Icon.refresh.image
                        .foregroundColor(colors.textSecondary)
                        .frame(width: 20, height: 20)
                        .opacity(isAgentTyping ? 0.4 : 1)
                        .onTapGesture {
                            guard !isAgentTyping else { return }
                            config.callbacks.onRegenerateClicked(message.id)
                            actions.onRegenerateClicked()
                        }
                }
                if config.features.showFeedback && config.features.showLike {
                    Chat360Icon.thumbUp.image
                        .foregroundColor(feedback == true ? colors.accentContrast : colors.textSecondary)
                        .frame(width: 18, height: 18)
                        .padding(6)
                        .background(feedback == true ? colors.accent : Color.clear)
                        .clipShape(Circle())
                        .onTapGesture {
                            // A dislike is permanent once set (it already had mandatory feedback
                            // submitted for it) - liking afterward can't override that. But like
                            // itself isn't locked from the other direction (see dislike below).
                            guard feedback == nil else { return }
                            feedback = true
                            actions.onLikeClicked()
                        }
                }
                if config.features.showFeedback && config.features.showDislike {
                    Chat360Icon.thumbDown.image
                        .foregroundColor(feedback == false ? colors.accentContrast : colors.textSecondary)
                        .frame(width: 18, height: 18)
                        .padding(6)
                        .background(feedback == false ? colors.accent : Color.clear)
                        .clipShape(Circle())
                        .onTapGesture {
                            // Only already-disliked is a no-op - switching from like to dislike
                            // is allowed, unlike the other direction, since dislike has its own
                            // mandatory feedback step gating it regardless.
                            guard feedback != false else { return }
                            feedback = false
                            actions.onDislikeClicked()
                        }
                }
            }
        }
        .onChange(of: initialReaction) { feedback = $0 }
    }
}
