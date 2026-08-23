import SwiftUI

@available(iOS 14.0, *)
public struct QuickReplyButton: View {
    @Environment(\.chat360Colors) private var colors
    @Environment(\.chat360Typography) private var typography

    private let text: String
    private let enabled: Bool
    private let selected: Bool
    private let onClick: () -> Void

    public init(text: String, enabled: Bool, selected: Bool, onClick: @escaping () -> Void) {
        self.text = text
        self.enabled = enabled
        self.selected = selected
        self.onClick = onClick
    }

    private var borderColor: Color {
        if selected { return colors.accent }
        if enabled { return colors.inputBorder }
        return colors.line
    }

    private var textColor: Color {
        if selected { return colors.accent }
        if enabled { return colors.textPrimary }
        return colors.textDisabled
    }

    public var body: some View {
        Button(action: onClick) {
            Text(text)
                .font(typography.textFamily.font(size: 14, weight: .medium))
                .foregroundColor(textColor)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .padding(.horizontal, 14)
                .overlay(RoundedRectangle(cornerRadius: 22).stroke(borderColor, lineWidth: 1))
        }
        .disabled(!enabled)
    }
}
