import SwiftUI

@available(iOS 14.0, *)
public struct ChatInputBar: View {
    @Environment(\.chat360Colors) private var colors
    @Environment(\.chat360Typography) private var typography
    @Environment(\.chat360Branding) private var branding

    @Binding private var value: String
    private let onSend: () -> Void
    private let onAttachmentClick: () -> Void
    private let onMicClick: () -> Void
    private let showDictationIcon: Bool
    private let onDictateClick: () -> Void
    private let onEmojiClick: () -> Void
    private let showAttachment: Bool
    private let showEmoji: Bool
    private let showVoiceInput: Bool
    private let showSend: Bool
    private let sendEnabled: Bool
    private let enabled: Bool

    public init(
        value: Binding<String>, onSend: @escaping () -> Void, onAttachmentClick: @escaping () -> Void,
        onMicClick: @escaping () -> Void, showDictationIcon: Bool = false, onDictateClick: @escaping () -> Void = {},
        onEmojiClick: @escaping () -> Void = {}, showAttachment: Bool = true, showEmoji: Bool = true,
        showVoiceInput: Bool = true, showSend: Bool = true, sendEnabled: Bool = true, enabled: Bool = true
    ) {
        self._value = value
        self.onSend = onSend
        self.onAttachmentClick = onAttachmentClick
        self.onMicClick = onMicClick
        self.showDictationIcon = showDictationIcon
        self.onDictateClick = onDictateClick
        self.onEmojiClick = onEmojiClick
        self.showAttachment = showAttachment
        self.showEmoji = showEmoji
        self.showVoiceInput = showVoiceInput
        self.showSend = showSend
        self.sendEnabled = sendEnabled
        self.enabled = enabled
    }

    public var body: some View {
        HStack(alignment: .center, spacing: 10) {
            if showAttachment {
                Button(action: onAttachmentClick) {
                    Chat360Icon.attachFile.image
                        .foregroundColor(enabled ? colors.textSecondary : colors.textDisabled)
                        .frame(width: 22, height: 22)
                }
                .disabled(!enabled)
            }
            if showDictationIcon {
                Button(action: onDictateClick) {
                    Chat360Icon.dictate.image
                        .foregroundColor(enabled ? colors.textSecondary : colors.textDisabled)
                        .frame(width: 22, height: 22)
                }
                .disabled(!enabled)
            }
            HStack(alignment: .center, spacing: 8) {
                ZStack(alignment: .leading) {
                    if value.isEmpty {
                        Text(branding.inputPlaceholder)
                            .font(typography.textFamily.font(size: 15))
                            .foregroundColor(colors.textSecondary)
                    }
                    TextField("", text: $value)
                        .font(typography.textFamily.font(size: 15))
                        .foregroundColor(colors.textPrimary)
                        .disabled(!enabled)
                        .accentColor(colors.accent)
                }
                .frame(maxWidth: .infinity)

                if showEmoji {
                    Text("🙂")
                        .font(.system(size: 18))
                        .onTapGesture { if enabled { onEmojiClick() } }
                }
                if showVoiceInput {
                    Button(action: onMicClick) {
                        Chat360Icon.mic.image
                            .foregroundColor(enabled ? colors.textSecondary : colors.textDisabled)
                            .frame(width: 20, height: 20)
                    }
                    .disabled(!enabled)
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 46)
            .background(colors.inputBackground)
            .overlay(Rectangle().stroke(colors.inputBorder, lineWidth: 1))

            if showSend {
                Button(action: onSend) {
                    Chat360Icon.arrowUp.image
                        .foregroundColor(colors.accentContrast)
                }
                .frame(width: 46, height: 46)
                .background((!enabled || !sendEnabled || value.isBlank) ? colors.textDisabled : colors.accent)
                .disabled(!enabled || !sendEnabled)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(colors.background)
        .overlay(Rectangle().frame(height: 1).foregroundColor(colors.line), alignment: .top)
    }
}
