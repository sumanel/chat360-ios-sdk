import SwiftUI

@available(iOS 14.0, *)
public struct SpeechToTextBar: View {
    @Environment(\.chat360Colors) private var colors
    @Environment(\.chat360Typography) private var typography

    private let isListening: Bool
    private let error: String?
    private let onStop: () -> Void

    public init(isListening: Bool, error: String?, onStop: @escaping () -> Void) {
        self.isListening = isListening
        self.error = error
        self.onStop = onStop
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                if isListening {
                    ProgressView().scaleEffect(0.7).progressViewStyle(CircularProgressViewStyle(tint: colors.accent))
                }
                Text(isListening ? "Listening…" : (error != nil ? "Error" : "Not listening"))
                    .font(typography.textFamily.font(size: 13))
                    .foregroundColor(colors.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button(action: onStop) {
                    Text("Stop")
                        .font(typography.textFamily.font(size: 13))
                        .foregroundColor(colors.textPrimary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(colors.backgroundSunken)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(colors.inputBackground)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(colors.inputBorder, lineWidth: 1))
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            if let error {
                Text(error)
                    .font(typography.textFamily.font(size: 12))
                    .foregroundColor(activeRed)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 4)
            }
        }
    }
}
