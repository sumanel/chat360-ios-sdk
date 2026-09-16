import SwiftUI

@available(iOS 15.0, *)
public struct DateSeparatorRow: View {
    @Environment(\.chat360Colors) private var colors
    @Environment(\.chat360Typography) private var typography

    private let label: String

    public init(label: String) {
        self.label = label
    }

    public var body: some View {
        HStack {
            Spacer()
            Text(label)
                .font(typography.textFamily.font(size: 12, weight: .semibold))
                .foregroundColor(colors.textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(colors.bubbleAiBackground)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(colors.cardBorder, lineWidth: 1))
            Spacer()
        }
    }
}
