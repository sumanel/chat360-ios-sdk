import SwiftUI

struct UserMessageRow: View {
    var message: ChatMessage

    @Environment(\.chat360Colors) private var colors
    @Environment(\.chat360Typography) private var typography

    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            Group {
                if let voiceMessage = message.voiceMessage {
                    VoiceMessageBubble(voiceMessage: voiceMessage)
                } else if let attachment = message.attachment {
                    AttachmentRow(attachment: attachment)
                } else {
                    Text(message.text)
                        .font(bodyFont)
                        .foregroundColor(colors.bubbleUserText)
                        .lineSpacing(7)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                }
            }
            .background(colors.bubbleUserBackground)
            .clipShape(RoundedRectangle(cornerRadius: 2))
            .frame(maxWidth: 300, alignment: .trailing)

            Spacer().frame(height: 4)
            Text(message.failed ? "Not delivered" : message.timeText)
                .font(textFont(size: 11))
                .foregroundColor(message.failed ? activeRed : colors.textDisabled)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private var bodyFont: Font {
        if let name = typography.textFontName { return .custom(name, size: 15) }
        return .system(size: 15)
    }

    private func textFont(size: CGFloat) -> Font {
        if let name = typography.textFontName { return .custom(name, size: size) }
        return .system(size: size)
    }
}

private struct AttachmentRow: View {
    var attachment: Attachment

    @Environment(\.chat360Colors) private var colors
    @Environment(\.chat360Typography) private var typography

    var body: some View {
        HStack(spacing: 8) {
            if attachment.failed || attachment.uploaded {
                Image(systemName: "doc.fill")
                    .foregroundColor(colors.bubbleUserText)
                    .frame(width: 18, height: 18)
            } else {
                ProgressView(value: Double(attachment.progress), total: 100)
                    .progressViewStyle(.circular)
                    .tint(colors.bubbleUserText)
                    .frame(width: 18, height: 18)
            }
            Text(label)
                .font(textFont(size: 14))
                .foregroundColor(colors.bubbleUserText)
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var label: String {
        if attachment.failed { return "\(attachment.fileName) (failed)" }
        if attachment.uploaded { return attachment.fileName }
        return "\(attachment.fileName) \(attachment.progress)%"
    }

    private func textFont(size: CGFloat) -> Font {
        if let name = typography.textFontName { return .custom(name, size: size) }
        return .system(size: size)
    }
}
