import SwiftUI

@available(iOS 14.0, *)
public struct UserMessageRow: View {
    @Environment(\.chat360Colors) private var colors
    @Environment(\.chat360Typography) private var typography

    private let message: ChatMessage

    public init(message: ChatMessage) {
        self.message = message
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
            Text(message.failed ? "Not delivered" : message.timeText)
                .font(typography.textFamily.font(size: 11))
                .foregroundColor(message.failed ? activeRed : colors.textDisabled)
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
