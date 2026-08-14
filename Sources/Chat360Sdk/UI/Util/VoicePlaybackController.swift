import Foundation
import AVFoundation

@available(iOS 13.0, *)
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

@available(iOS 13.0, *)
@MainActor
public final class VoicePlaybackController: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published public private(set) var isPlaying = false
    @Published public private(set) var positionMs = 0
    @Published public private(set) var durationMs = 0

    private var player: AVAudioPlayer?
    private var ticker: Timer?
    private var loadedSource: String?

    public override init() {
        super.init()
    }

    public func playOrPause(localFilePath: String?, remoteUrl: String?) {
        if isPlaying {
            pause()
            return
        }
        let source: String
        if let localFilePath, FileManager.default.fileExists(atPath: localFilePath) {
            source = localFilePath
        } else if let remoteUrl {
            source = remoteUrl
        } else {
            return
        }

        if loadedSource == source, let player {
            player.play()
            isPlaying = true
            VoicePlaybackCoordinator.shared.onPlay(self)
            startTicker()
            return
        }

        guard let url = source.hasPrefix("http") ? URL(string: source) : URL(fileURLWithPath: source) else { return }
        if source.hasPrefix("http") {
            URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
                guard let self, let data else { return }
                Task { @MainActor in
                    self.startPlayback(data: data, source: source)
                }
            }.resume()
        } else {
            guard let data = try? Data(contentsOf: url) else { return }
            startPlayback(data: data, source: source)
        }
    }

    private func startPlayback(data: Data, source: String) {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            let newPlayer = try AVAudioPlayer(data: data)
            newPlayer.delegate = self
            newPlayer.play()
            player = newPlayer
            loadedSource = source
            durationMs = Int(newPlayer.duration * 1000)
            isPlaying = true
            VoicePlaybackCoordinator.shared.onPlay(self)
            startTicker()
        } catch {
            isPlaying = false
            loadedSource = nil
        }
    }

    public func pause() {
        player?.pause()
        isPlaying = false
        ticker?.invalidate()
        ticker = nil
    }

    private func startTicker() {
        ticker?.invalidate()
        ticker = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let player = self.player else { return }
                self.positionMs = Int(player.currentTime * 1000)
            }
        }
    }

    public nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.isPlaying = false
            self.positionMs = 0
            self.ticker?.invalidate()
            self.ticker = nil
            VoicePlaybackCoordinator.shared.onStop(self)
        }
    }

    public func release() {
        ticker?.invalidate()
        ticker = nil
        VoicePlaybackCoordinator.shared.onStop(self)
        player?.stop()
        player = nil
        isPlaying = false
        loadedSource = nil
        positionMs = 0
        durationMs = 0
    }
}
