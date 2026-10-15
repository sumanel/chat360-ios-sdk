import SwiftUI

/// Which rating a feedback dialog collects a reason for. A dislike needs a reason (the feedback API rejects one
/// without a remark); a like asks for one too, but it is optional.
@available(iOS 16.0, *)
public enum FeedbackDialogKind {
    case dislike
    case like
    /// Feedback about the whole application, from the drawer.
    case appFeedback

    var title: String {
        switch self {
        case .dislike: return "Help us improve"
        case .like: return "What did you like?"
        case .appFeedback: return "Share your feedback"
        }
    }
    var prompt: String {
        switch self {
        case .dislike: return "Please tell us what went wrong with this response before continuing."
        case .like: return "Tell us what was helpful about this response (optional)."
        case .appFeedback: return "Tell us about your experience with the app."
        }
    }
    var minCharCount: Int {
        switch self {
        case .dislike: return 20
        case .like: return 0
        case .appFeedback: return 1
        }
    }

    func counterText(charCount: Int) -> String {
        switch minCharCount {
        case 0: return "Optional"
        case 1: return "Required"
        default: return "\(min(charCount, minCharCount))/\(minCharCount) characters minimum"
        }
    }
}

/// The text to send as the remark: trimmed, or nil (nothing sent) when the user typed nothing.
func normalizedFeedbackRemarks(_ text: String) -> String? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}

@available(iOS 16.0, *)
public struct DislikeFeedbackDialog: View {
    @Environment(\.chat360Colors) private var colors
    @Environment(\.chat360Typography) private var typography

    private let kind: FeedbackDialogKind
    private let isSending: Bool
    private let errorMessage: String?
    private let onSubmit: (String) -> Void
    private let onCancel: () -> Void

    @State private var text = ""

    public init(
        kind: FeedbackDialogKind = .dislike, isSending: Bool = false, errorMessage: String? = nil,
        onSubmit: @escaping (String) -> Void, onCancel: @escaping () -> Void
    ) {
        self.kind = kind
        self.isSending = isSending
        self.errorMessage = errorMessage
        self.onSubmit = onSubmit
        self.onCancel = onCancel
    }

    private var charCount: Int {
        text.trimmingCharacters(in: .whitespacesAndNewlines).count
    }

    private var canSubmit: Bool { charCount >= kind.minCharCount && !isSending }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                Text(kind.title)
                    .font(typography.textFamily.font(size: 16, weight: .semibold))
                    .foregroundColor(colors.textPrimary)
                Spacer()
                // Undoes the dislike itself (reaction reverts, obligation clears) - it is not a
                // skip button, so this can't just dismiss and leave feedback owed.
                Button(action: onCancel) {
                    Chat360Icon.close.image
                        .foregroundColor(colors.textSecondary)
                        .frame(width: 24, height: 24)
                }
            }
            Spacer().frame(height: 6)
            Text(kind.prompt)
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
            Text(kind.counterText(charCount: charCount))
                .font(typography.textFamily.font(size: 12))
                .foregroundColor(canSubmit ? colors.textSecondary : activeRed)
            if let errorMessage {
                Spacer().frame(height: 6)
                Text(errorMessage)
                    .font(typography.textFamily.font(size: 12))
                    .foregroundColor(activeRed)
            }
            Spacer().frame(height: 16)
            Button(action: { onSubmit(text) }) {
                Text(isSending ? "Sending…" : "Submit")
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
