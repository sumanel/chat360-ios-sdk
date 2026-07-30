import SwiftUI

private func formatMs(_ ms: Int64) -> String {
    let totalSec = ms / 1000
    return String(format: "%d:%02d", totalSec / 60, totalSec % 60)
}

/// Swaps in for `ChatInputBar`'s whole row while a voice note is being recorded or reviewed:
/// recording -> waveform+cancel+stop, review -> play/delete/send with upload progress/error.
struct VoiceRecorderBar: View {
    var isRecording: Bool
    var liveAmplitudes: [Int]
    var elapsedMs: Int64
    var onStopRecording: () -> Void
    var onCancelRecording: () -> Void
    var draftAmplitudes: [Int]
    var draftDurationMs: Int64
    var draftUploading: Bool
    var draftUploadProgress: Int
    var draftError: String?
    @ObservedObject var playbackController: VoicePlaybackController
    var draftLocalFilePath: String?
    var onSendDraft: () -> Void
    var onCancelDraft: () -> Void

    @Environment(\.chat360Colors) private var colors
    @Environment(\.chat360Typography) private var typography

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let draftError {
                Text(draftError)
                    .font(textFont(size: 12))
                    .foregroundColor(activeRed)
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
            }
            HStack(spacing: 10) {
                Button(action: isRecording ? onCancelRecording : onCancelDraft) {
                    Image(systemName: "xmark")
                        .foregroundColor(activeRed)
                        .frame(width: 20, height: 20)
                        .padding(6)
                }
                .disabled(draftUploading)

                if isRecording {
                    VoiceWaveformBars(amplitudes: liveAmplitudes, color: colors.accent, progress: nil)
                        .frame(maxWidth: .infinity)
                    Text(formatMs(elapsedMs)).font(textFont(size: 13)).foregroundColor(colors.textSecondary)
                    Button(action: onStopRecording) {
                        Image(systemName: "checkmark")
                            .foregroundColor(colors.accent)
                            .frame(width: 22, height: 22)
                            .padding(6)
                    }
                } else {
                    let progress = playbackController.durationMs > 0 ? Double(playbackController.positionMs) / Double(playbackController.durationMs) : 0
                    Button(action: { playbackController.playOrPause(localFilePath: draftLocalFilePath, remoteUrl: nil) }) {
                        Image(systemName: playbackController.isPlaying ? "pause.fill" : "play.fill")
                            .foregroundColor(colors.accent)
                            .frame(width: 20, height: 20)
                            .padding(6)
                    }
                    .disabled(draftUploading)

                    VoiceWaveformBars(amplitudes: draftAmplitudes, color: colors.accent, progress: progress)
                        .frame(maxWidth: .infinity)

                    Text(formatMs(draftDurationMs) + (draftUploading ? " · \(draftUploadProgress)%" : ""))
                        .font(textFont(size: 12))
                        .foregroundColor(colors.textSecondary)

                    Button(action: onSendDraft) {
                        ZStack {
                            Circle().fill(colors.accent)
                            if draftUploading {
                                ProgressView().tint(colors.accentContrast).scaleEffect(0.7)
                            } else {
                                Image(systemName: "arrow.up").foregroundColor(colors.accentContrast).font(.system(size: 14))
                            }
                        }
                        .frame(width: 32, height: 32)
                    }
                    .disabled(draftUploading)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(colors.inputBackground)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(colors.inputBorder, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
    }

    private func textFont(size: CGFloat) -> Font {
        if let name = typography.textFontName { return .custom(name, size: size) }
        return .system(size: size)
    }
}
