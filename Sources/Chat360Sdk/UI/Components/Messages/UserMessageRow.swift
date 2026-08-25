import SwiftUI

@available(iOS 14.0, *)
public struct UserMessageRow: View {
    @Environment(\.chat360Colors) private var colors
    @Environment(\.chat360Typography) private var typography

    private let message: ChatMessage
    // Covers every way a reply can end up never arriving - a plain delivery-ack timeout, and the
    // room being found still owed a reply (see `backfillMissingReplies`'s stale-threshold check)
    // after the app was restarted or backgrounded while the bot was generating - all of them
    // converge on the same `message.failed` flag, so one tap target here covers all of them.
    private let onRetry: () -> Void

    public init(message: ChatMessage, onRetry: @escaping () -> Void = {}) {
        self.message = message
        self.onRetry = onRetry
    }

    public var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            Group {
                if let voiceMessage = message.voiceMessage {
                    VoiceMessageBubble(voiceMessage: voiceMessage)
                } else if let attachment = message.attachment {
                    AttachmentRow(attachment: attachment)
                } else {
                    Text(message.text)
                        .font(typography.textFamily.font(size: 15))
                        .lineSpacing(7)
                        .foregroundColor(colors.bubbleUserText)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                }
            }
            .background(colors.bubbleUserBackground)
            .clipShape(RoundedRectangle(cornerRadius: 2))
            .frame(maxWidth: 300, alignment: .trailing)

            Spacer().frame(height: 4)
            Text(message.failed ? "Not delivered · Tap to retry" : message.timeText)
                .font(typography.textFamily.font(size: 11))
                .foregroundColor(message.failed ? activeRed : colors.textDisabled)
                .onTapGesture {
                    guard message.failed else { return }
                    onRetry()
                }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

@available(iOS 14.0, *)
private struct AttachmentRow: View {
    @Environment(\.chat360Colors) private var colors
    @Environment(\.chat360Typography) private var typography
    let attachment: Attachment

    var body: some View {
        HStack(spacing: 8) {
            if attachment.failed || attachment.uploaded {
                Chat360Icon.attachFile.image
                    .foregroundColor(colors.bubbleUserText)
                    .frame(width: 18, height: 18)
            } else {
                ProgressView(value: Double(attachment.progress) / 100)
                    .progressViewStyle(CircularProgressViewStyle(tint: colors.bubbleUserText))
                    .frame(width: 18, height: 18)
            }
            Text(labelText)
                .font(typography.textFamily.font(size: 14))
                .foregroundColor(colors.bubbleUserText)
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var labelText: String {
        if attachment.failed { return "\(attachment.fileName) (failed)" }
        if attachment.uploaded { return attachment.fileName }
        return "\(attachment.fileName) \(attachment.progress)%"
    }
}
