import SwiftUI

struct ChatInputBar: View {
    @Binding var value: String
    var onSend: () -> Void
    var onMicClick: () -> Void

    @Environment(\.chat360Colors) private var colors
    @Environment(\.chat360Typography) private var typography
    @Environment(\.chat360Branding) private var branding

    var body: some View {
        HStack(alignment: .center, spacing: 0) {

            HStack(spacing: 0) {
                TextField(branding.inputPlaceholder, text: $value)
                    .font(bodyFont)
                    .foregroundColor(colors.textPrimary)
                    .tint(colors.accent)
                    .padding(.vertical, 12)

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
            .overlay(Rectangle().stroke(colors.inputBorder, lineWidth: 1))

            Spacer().frame(width: 10)

            Button(action: onSend) {
                Image(systemName: "arrow.up")
                    .foregroundColor(colors.accentContrast)
                    .frame(width: 48, height: 48)
                    .background(value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? colors.textDisabled : colors.accent)
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
