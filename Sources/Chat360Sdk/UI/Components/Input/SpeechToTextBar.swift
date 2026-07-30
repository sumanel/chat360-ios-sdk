import SwiftUI

/// The compact "Listening…"/Stop indicator shown while dictating - no waveform of its own; that's
/// `VoiceRecorderBar`'s domain for actual voice-message capture, a deliberately separate concern
/// from text dictation.
struct SpeechToTextBar: View {
    var isListening: Bool
    var error: String?
    var onStop: () -> Void

    @Environment(\.chat360Colors) private var colors
    @Environment(\.chat360Typography) private var typography

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                if isListening {
                    ProgressView().tint(colors.accent).scaleEffect(0.6)
                }
                Text(isListening ? "Listening…" : (error != nil ? "Error" : "Not listening"))
                    .font(textFont(size: 13))
                    .foregroundColor(colors.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button(action: onStop) {
                    Text("Stop")
                        .font(textFont(size: 13))
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
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            if let error {
                Text(error)
                    .font(textFont(size: 12))
                    .foregroundColor(activeRed)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 4)
            }
        }
    }

    private func textFont(size: CGFloat) -> Font {
        if let name = typography.textFontName { return .custom(name, size: size) }
        return .system(size: size)
    }
}
