import SwiftUI

@available(iOS 14.0, *)
private func formatMs(_ ms: Int64) -> String {
    let totalSec = ms / 1000
    return String(format: "%d:%02d", totalSec / 60, totalSec % 60)
}

@available(iOS 14.0, *)
public struct VoiceRecorderBar: View {
    @Environment(\.chat360Colors) private var colors
    @Environment(\.chat360Typography) private var typography
    @ObservedObject private var playbackController: VoicePlaybackController

    private let isRecording: Bool
    private let liveAmplitudes: [Int]
    private let elapsedMs: Int64
    private let onStopRecording: () -> Void
    private let onCancelRecording: () -> Void
    private let draftAmplitudes: [Int]
    private let draftDurationMs: Int64
    private let draftUploading: Bool
    private let draftUploadProgress: Int
    private let draftError: String?
    private let draftLocalFilePath: String?
    private let onSendDraft: () -> Void
    private let onCancelDraft: () -> Void

    public init(
        isRecording: Bool, liveAmplitudes: [Int], elapsedMs: Int64, onStopRecording: @escaping () -> Void,
        onCancelRecording: @escaping () -> Void, draftAmplitudes: [Int], draftDurationMs: Int64, draftUploading: Bool,
        draftUploadProgress: Int, draftError: String?, playbackController: VoicePlaybackController, draftLocalFilePath: String?,
        onSendDraft: @escaping () -> Void, onCancelDraft: @escaping () -> Void
    ) {
        self.isRecording = isRecording
        self.liveAmplitudes = liveAmplitudes
        self.elapsedMs = elapsedMs
        self.onStopRecording = onStopRecording
        self.onCancelRecording = onCancelRecording
        self.draftAmplitudes = draftAmplitudes
        self.draftDurationMs = draftDurationMs
        self.draftUploading = draftUploading
        self.draftUploadProgress = draftUploadProgress
        self.draftError = draftError
        self.playbackController = playbackController
        self.draftLocalFilePath = draftLocalFilePath
        self.onSendDraft = onSendDraft
        self.onCancelDraft = onCancelDraft
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let draftError {
                Text(draftError)
                    .font(typography.textFamily.font(size: 12))
                    .foregroundColor(activeRed)
                    .padding(.leading, 16)
                    .padding(.trailing, 16)
                    .padding(.top, 4)
            }
            HStack(spacing: 0) {
                Button(action: isRecording ? onCancelRecording : onCancelDraft) {
                    Chat360Icon.close.image
                        .foregroundColor(activeRed)
                        .padding(6)
                        .frame(width: 20, height: 20)
                }
                .disabled(draftUploading)
                Spacer().frame(width: 10)

                if isRecording {
                    VoiceWaveformBars(amplitudes: liveAmplitudes, color: colors.accent, progress: nil)
                        .frame(maxWidth: .infinity)
                    Spacer().frame(width: 10)
                    Text(formatMs(elapsedMs))
                        .font(typography.textFamily.font(size: 13))
                        .foregroundColor(colors.textSecondary)
                    Spacer().frame(width: 12)
                    Button(action: onStopRecording) {
                        Chat360Icon.check.image
                            .foregroundColor(colors.accent)
                            .padding(6)
                            .frame(width: 22, height: 22)
                    }
                } else {
                    let progress = playbackController.durationMs > 0 ? Double(playbackController.positionMs) / Double(playbackController.durationMs) : 0
                    Button(action: { playbackController.playOrPause(localFilePath: draftLocalFilePath, remoteUrl: nil) }) {
                        (playbackController.isPlaying ? Chat360Icon.pause : Chat360Icon.play).image
                            .foregroundColor(colors.accent)
                            .padding(6)
                            .frame(width: 20, height: 20)
                    }
                    .disabled(draftUploading)
                    Spacer().frame(width: 6)
                    VoiceWaveformBars(amplitudes: draftAmplitudes, color: colors.accent, progress: progress)
                        .frame(maxWidth: .infinity)
                    Spacer().frame(width: 10)
                    Text(formatMs(draftDurationMs) + (draftUploading ? " · \(draftUploadProgress)%" : ""))
                        .font(typography.textFamily.font(size: 12))
                        .foregroundColor(colors.textSecondary)
                    Spacer().frame(width: 12)
                    Button(action: onSendDraft) {
                        ZStack {
                            Circle().fill(colors.accent).frame(width: 32, height: 32)
                            if draftUploading {
                                ProgressView().scaleEffect(0.6).progressViewStyle(CircularProgressViewStyle(tint: colors.accentContrast))
                            } else {
                                Chat360Icon.arrowUp.image.foregroundColor(colors.accentContrast).font(.system(size: 14))
                            }
                        }
                    }
                    .disabled(draftUploading)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(colors.inputBackground)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(colors.inputBorder, lineWidth: 1))
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
    }
}
