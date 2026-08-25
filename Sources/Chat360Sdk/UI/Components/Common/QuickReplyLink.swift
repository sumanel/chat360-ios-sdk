import SwiftUI

// Renders a nudge option as underlined accent-colored text (comma-separated when several are
// shown together via `FlowLayout`, see `MultiChoiceContent`) instead of a bordered button - the
// `text` a caller passes in already carries any trailing separator (e.g. a comma for every
// option but the last).
@available(iOS 14.0, *)
public struct QuickReplyLink: View {
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

    private var textColor: Color {
        if selected { return colors.accent }
        if enabled { return colors.accent }
        return colors.textDisabled
    }

    public var body: some View {
        Button(action: onClick) {
            Text(text)
                .font(typography.textFamily.font(size: 14, weight: selected ? .semibold : .medium))
                .foregroundColor(textColor)
                .underline(true, color: textColor)
        }
        .disabled(!enabled)
    }
}
