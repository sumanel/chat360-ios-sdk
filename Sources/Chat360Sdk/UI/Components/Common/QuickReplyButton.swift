import SwiftUI

/// Pill-shaped choice button used by MULTI_CHOICE nodes (and any future button-based content).
struct QuickReplyButton: View {
    var text: String
    var enabled: Bool
    var selected: Bool
    var onTap: () -> Void

    @Environment(\.chat360Colors) private var colors
    @Environment(\.chat360Typography) private var typography

    private var borderColor: Color {
        if selected { return colors.accent }
        return enabled ? colors.inputBorder : colors.line
    }

    private var textColor: Color {
        if selected { return colors.accent }
        return enabled ? colors.textPrimary : colors.textDisabled
    }

    var body: some View {
        Button(action: onTap) {
            Text(text)
                .font(bodyFont)
                .fontWeight(.medium)
                .foregroundColor(textColor)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
                .overlay(RoundedRectangle(cornerRadius: 22).stroke(borderColor, lineWidth: 1))
        }
        .disabled(!enabled)
        .buttonStyle(.plain)
    }

    private var bodyFont: Font {
        if let name = typography.textFontName { return .custom(name, size: 14) }
        return .system(size: 14)
    }
}
