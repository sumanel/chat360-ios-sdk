import SwiftUI

@available(iOS 15.0, *)
public struct MultiOptionContent: View {
    @Environment(\.chat360Colors) private var colors
    @Environment(\.chat360Typography) private var typography

    private let message: ChatMessage
    private let content: BotContent.MultiOption
    private let isLiveChat: Bool
    private let onToggle: (Int) -> Void
    private let onSubmit: () -> Void

    public init(message: ChatMessage, content: BotContent.MultiOption, isLiveChat: Bool, onToggle: @escaping (Int) -> Void, onSubmit: @escaping () -> Void) {
        self.message = message
        self.content = content
        self.isLiveChat = isLiveChat
        self.onToggle = onToggle
        self.onSubmit = onSubmit
    }

    private var enabled: Bool { message.repliesEnabled && !isLiveChat }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let description = content.description {
                Text(description).font(typography.textFamily.font(size: 13)).foregroundColor(colors.textSecondary)
                Spacer().frame(height: 6)
            }
            ForEach(content.options, id: \.index) { option in
                HStack {
                    Button(action: { onToggle(option.index) }) {
                        Image(systemName: message.checkedIndices.contains(option.index) ? "checkmark.square.fill" : "square")
                            .foregroundColor(message.checkedIndices.contains(option.index) ? colors.accent : colors.textSecondary)
                    }
                    .disabled(!enabled)
                    Text(option.text).font(typography.textFamily.font(size: 14)).foregroundColor(colors.textPrimary)
                }
            }
            Spacer().frame(height: 8)
            Button(action: onSubmit) {
                Text("Submit")
                    .font(typography.textFamily.font(size: 15))
                    .foregroundColor(colors.accentContrast)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background((enabled && !message.checkedIndices.isEmpty) ? colors.accent : colors.textDisabled)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .disabled(!(enabled && !message.checkedIndices.isEmpty))
        }
    }
}
