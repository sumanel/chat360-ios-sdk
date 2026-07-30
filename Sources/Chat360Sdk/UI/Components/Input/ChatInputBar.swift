import SwiftUI

struct ChatInputBar: View {
    @Binding var value: String
    var onSend: () -> Void
    var onAttachmentClick: () -> Void
    var onMicClick: () -> Void
    var showDictationIcon: Bool = false
    var onDictateClick: () -> Void = {}
    var onEmojiClick: () -> Void = {}

    @Environment(\.chat360Colors) private var colors
    @Environment(\.chat360Typography) private var typography
    @Environment(\.chat360Branding) private var branding

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            Button(action: onAttachmentClick) {
                Image(systemName: "paperclip")
                    .foregroundColor(colors.textSecondary)
                    .frame(width: 24, height: 24)
                    .padding(8)
            }

            if showDictationIcon {
                Button(action: onDictateClick) {
                    Image(systemName: "waveform")
                        .foregroundColor(colors.textSecondary)
                        .frame(width: 22, height: 22)
                        .padding(8)
                }
            }

            HStack(spacing: 0) {
                TextField(branding.inputPlaceholder, text: $value)
                    .font(bodyFont)
                    .foregroundColor(colors.textPrimary)
                    .tint(colors.accent)
                    .padding(.vertical, 12)

                Button(action: onEmojiClick) {
                    Text("🙂").font(.system(size: 18))
                }
                .padding(6)

                Button(action: onMicClick) {
                    Image(systemName: "mic.fill")
                        .foregroundColor(colors.textSecondary)
                        .frame(width: 20, height: 20)
                        .padding(8)
                }
            }
            .padding(.leading, 14)
            .padding(.trailing, 4)
            .background(colors.inputBackground)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(colors.inputBorder, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 10))

            Spacer().frame(width: 10)

            Button(action: onSend) {
                Image(systemName: "arrow.up")
                    .foregroundColor(colors.accentContrast)
                    .frame(width: 48, height: 48)
                    .background(value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? colors.textDisabled : colors.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var bodyFont: Font {
        if let name = typography.textFontName { return .custom(name, size: 15) }
        return .system(size: 15)
    }
}
