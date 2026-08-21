import SwiftUI

@available(iOS 16.0, *)
public struct DislikeFeedbackDialog: View {
    @Environment(\.chat360Colors) private var colors
    @Environment(\.chat360Typography) private var typography

    private static let minWordCount = 20

    private let onSubmit: (String) -> Void

    @State private var text = ""

    public init(onSubmit: @escaping (String) -> Void) {
        self.onSubmit = onSubmit
    }

    private var wordCount: Int {
        text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }

    private var canSubmit: Bool { wordCount >= Self.minWordCount }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Help us improve")
                .font(typography.textFamily.font(size: 16, weight: .semibold))
                .foregroundColor(colors.textPrimary)
            Spacer().frame(height: 6)
            Text("Please tell us what went wrong with this response before continuing.")
                .font(typography.textFamily.font(size: 13))
                .foregroundColor(colors.textSecondary)
            Spacer().frame(height: 14)
            TextEditor(text: $text)
                .font(typography.textFamily.font(size: 14))
                .foregroundColor(colors.textPrimary)
                .scrollContentBackground(.hidden)
                .frame(height: 140)
                .padding(8)
                .background(colors.inputBackground)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            Spacer().frame(height: 6)
            Text("\(min(wordCount, Self.minWordCount))/\(Self.minWordCount) words minimum")
                .font(typography.textFamily.font(size: 12))
                .foregroundColor(canSubmit ? colors.textSecondary : activeRed)
            Spacer().frame(height: 16)
            Button(action: { onSubmit(text) }) {
                Text("Submit")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .foregroundColor(colors.accentContrast)
                    .background(canSubmit ? colors.accent : colors.textDisabled)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .disabled(!canSubmit)
        }
        .padding(20)
        .background(colors.backgroundElevated)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .padding(.horizontal, 16)
    }
}
