import SwiftUI

@available(iOS 14.0, *)
public struct VoiceMessageBubble: View {
    @Environment(\.chat360Colors) private var colors
    @Environment(\.chat360Typography) private var typography
    @StateObject private var playback = VoicePlaybackController()

    private let voiceMessage: VoiceMessageInfo

    public init(voiceMessage: VoiceMessageInfo) {
        self.voiceMessage = voiceMessage
    }

    private var progress: Double {
        playback.durationMs > 0 ? Double(playback.positionMs) / Double(playback.durationMs) : 0
    }

    private var displaySec: Int64 {
        let totalMs = playback.durationMs > 0 ? Int64(playback.durationMs) : voiceMessage.durationMs
        let totalSec = totalMs / 1000
        return (playback.isPlaying || playback.positionMs > 0) ? Int64(playback.positionMs) / 1000 : totalSec
    }

    public var body: some View {
        HStack(spacing: 8) {
            Button(action: { playback.playOrPause(localFilePath: voiceMessage.localFilePath, remoteUrl: voiceMessage.remoteUrl) }) {
                (playback.isPlaying ? Chat360Icon.pause : Chat360Icon.play).image
                    .foregroundColor(colors.bubbleUserText)
                    .padding(6)
                    .background(colors.bubbleUserText.opacity(0.15))
                    .clipShape(Circle())
                    .frame(width: 18, height: 18)
            }
            VoiceWaveformBars(amplitudes: voiceMessage.amplitudes, color: colors.bubbleUserText, progress: progress)
            Text(String(format: "%d:%02d", displaySec / 60, displaySec % 60))
                .font(typography.textFamily.font(size: 11))
                .foregroundColor(colors.bubbleUserText)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
    }
}
