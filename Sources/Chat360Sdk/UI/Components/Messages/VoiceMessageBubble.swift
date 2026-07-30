import SwiftUI

/// The sent-bubble player (Audio + duration text underneath).
struct VoiceMessageBubble: View {
    var voiceMessage: VoiceMessageInfo

    @Environment(\.chat360Colors) private var colors
    @Environment(\.chat360Typography) private var typography
    @StateObject private var playback = VoicePlaybackController()

    private var progress: Double {
        playback.durationMs > 0 ? Double(playback.positionMs) / Double(playback.durationMs) : 0
    }

    private var totalSec: Int64 {
        playback.durationMs > 0 ? Int64(playback.durationMs / 1000) : voiceMessage.durationMs / 1000
    }

    private var displaySec: Int64 {
        (playback.isPlaying || playback.positionMs > 0) ? Int64(playback.positionMs / 1000) : totalSec
    }

    var body: some View {
        HStack(spacing: 8) {
            Button(action: { playback.playOrPause(localFilePath: voiceMessage.localFilePath, remoteUrl: voiceMessage.remoteUrl) }) {
                Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                    .foregroundColor(colors.bubbleUserText)
                    .padding(6)
                    .background(colors.bubbleUserText.opacity(0.15))
                    .clipShape(Circle())
            }
            VoiceWaveformBars(amplitudes: voiceMessage.amplitudes, color: colors.bubbleUserText, progress: progress)
            Text(String(format: "%d:%02d", displaySec / 60, displaySec % 60))
                .font(textFont(size: 11))
                .foregroundColor(colors.bubbleUserText)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
    }

    private func textFont(size: CGFloat) -> Font {
        if let name = typography.textFontName { return .custom(name, size: size) }
        return .system(size: size)
    }
}
