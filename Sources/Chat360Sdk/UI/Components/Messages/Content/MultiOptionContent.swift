import SwiftUI

/// A checkbox list (unlike MultiChoice, more than one can be checked).
struct MultiOptionContent: View {
    var message: ChatMessage
    var content: BotContent.MultiOption
    var isLiveChat: Bool
    var onToggle: (Int) -> Void
    var onSubmit: () -> Void

    @Environment(\.chat360Colors) private var colors
    @Environment(\.chat360Typography) private var typography

    private var enabled: Bool { message.repliesEnabled && !isLiveChat }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let description = content.description {
                Text(description).font(textFont(size: 13)).foregroundColor(colors.textSecondary)
            }
            ForEach(content.options, id: \.index) { option in
                Button(action: { onToggle(option.index) }) {
                    HStack {
                        Image(systemName: message.checkedIndices.contains(option.index) ? "checkmark.square.fill" : "square")
                            .foregroundColor(message.checkedIndices.contains(option.index) ? colors.accent : colors.textSecondary)
                        Text(option.text).font(textFont(size: 14)).foregroundColor(colors.textPrimary)
                    }
                }
                .disabled(!enabled)
                .buttonStyle(.plain)
            }
            Button(action: onSubmit) {
                Text("Submit")
                    .font(textFont(size: 14))
                    .foregroundColor(colors.accentContrast)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(enabled && !message.checkedIndices.isEmpty ? colors.accent : colors.textDisabled)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .disabled(!(enabled && !message.checkedIndices.isEmpty))
        }
    }

    private func textFont(size: CGFloat) -> Font {
        if let name = typography.textFontName { return .custom(name, size: size) }
        return .system(size: size)
    }
}
