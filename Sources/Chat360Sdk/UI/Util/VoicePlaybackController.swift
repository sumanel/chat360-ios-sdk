import Foundation
import AVFoundation

/// Ensures only one voice bubble plays at a time - a new `playOrPause` here pauses whichever
/// controller currently holds playback. Controllers register themselves on play and stop.
@MainActor
private final class VoicePlaybackCoordinator {
    static let shared = VoicePlaybackCoordinator()
    private weak var current: VoicePlaybackController?

    func onPlay(_ controller: VoicePlaybackController) {
        if current !== controller { current?.pause() }
        current = controller
    }

    func onStop(_ controller: VoicePlaybackController) {
        if current === controller { current = nil }
    }
}

/// Plays either a local file path or a remote URL - a sent bubble prefers `localFilePath`
/// (instant, no network wait). Backed by `AVPlayer` (rather than `AVAudioPlayer`) specifically so
/// a remote URL streams instead of requiring a blocking full-file download first.
@MainActor
final class VoicePlaybackController: ObservableObject {
    @Published private(set) var isPlaying = false
    @Published private(set) var positionMs: Int = 0
    @Published private(set) var durationMs: Int = 0

    private var player: AVPlayer?
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var loadedSource: String?

    func playOrPause(localFilePath: String?, remoteUrl: String?) {
        if isPlaying {
            pause()
            return
        }
        guard let url = resolveURL(localFilePath: localFilePath, remoteUrl: remoteUrl) else { return }

        if let player, loadedSource == url.absoluteString {
            // Resuming from pause, or replaying after completion (end handler already seeked to 0).
            player.play()
            isPlaying = true
            VoicePlaybackCoordinator.shared.onPlay(self)
            return
        }

        teardownObservers()
        let item = AVPlayerItem(url: url)
        let newPlayer = AVPlayer(playerItem: item)
        player = newPlayer
        loadedSource = url.absoluteString

        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.isPlaying = false
                self.positionMs = 0
                self.player?.seek(to: .zero)
                VoicePlaybackCoordinator.shared.onStop(self)
            }
        }
        timeObserver = newPlayer.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.1, preferredTimescale: 600), queue: .main) { [weak self] time in
            guard let self else { return }
            self.positionMs = Int(time.seconds * 1000)
            if let duration = newPlayer.currentItem?.duration, duration.isNumeric {
                self.durationMs = Int(duration.seconds * 1000)
            }
        }

        newPlayer.play()
        isPlaying = true
        VoicePlaybackCoordinator.shared.onPlay(self)
    }

    func pause() {
        player?.pause()
        isPlaying = false
    }

    func release() {
        teardownObservers()
        player = nil
        VoicePlaybackCoordinator.shared.onStop(self)
        isPlaying = false
        loadedSource = nil
        positionMs = 0
        durationMs = 0
    }

    private func resolveURL(localFilePath: String?, remoteUrl: String?) -> URL? {
        if let localFilePath, FileManager.default.fileExists(atPath: localFilePath) {
            return URL(fileURLWithPath: localFilePath)
        }
        if let remoteUrl { return URL(string: remoteUrl) }
        return nil
    }

    private func teardownObservers() {
        if let timeObserver, let player { player.removeTimeObserver(timeObserver) }
        timeObserver = nil
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
    }
}
