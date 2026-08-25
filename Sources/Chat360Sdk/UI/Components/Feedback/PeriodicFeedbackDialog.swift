import SwiftUI

// A periodic "how's it going" prompt shown every random 3-5 live bot replies, distinct from the
// per-message dislike dialog it's visually modeled on - unlike that one, there's no cancel path
// here at all (no X, nothing to undo), since this isn't gating any single message's reaction.
@available(iOS 16.0, *)
public struct PeriodicFeedbackDialog: View {
    @Environment(\.chat360Colors) private var colors
    @Environment(\.chat360Typography) private var typography

    private static let minCharCount = 20

    private let onSubmit: (String) -> Void

    @State private var text = ""

    public init(onSubmit: @escaping (String) -> Void) {
        self.onSubmit = onSubmit
    }

    private var charCount: Int {
        text.trimmingCharacters(in: .whitespacesAndNewlines).count
    }

    private var canSubmit: Bool { charCount >= Self.minCharCount }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("How's it going so far?")
                .font(typography.textFamily.font(size: 16, weight: .semibold))
                .foregroundColor(colors.textPrimary)
            Spacer().frame(height: 6)
            Text("Your feedback helps us improve this conversation.")
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
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(colors.inputBorder, lineWidth: 1))
            Spacer().frame(height: 6)
            Text("\(min(charCount, Self.minCharCount))/\(Self.minCharCount) characters minimum")
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
