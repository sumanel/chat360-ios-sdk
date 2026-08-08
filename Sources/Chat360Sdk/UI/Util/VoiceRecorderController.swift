import Foundation
import AVFoundation

/// One completed take: the encoded audio file plus the amplitude samples captured while recording.
struct VoiceRecording {
    var fileURL: URL
    var amplitudes: [Int]
    var durationMs: Int64
}

private let sampleIntervalSeconds: TimeInterval = 0.1
private let maxSamples = 60

/// Records a voice note via `AVAudioRecorder` (AAC/m4a format).
/// `amplitudes`/`isRecording`/`elapsedMs` are `@Published` so a live waveform can
/// observe them directly.
@MainActor
final class VoiceRecorderController: NSObject, ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var amplitudes: [Int] = []
    @Published private(set) var elapsedMs: Int64 = 0

    private var recorder: AVAudioRecorder?
    private var outputURL: URL?
    private var startedAt: Date?
    private var timer: Timer?
    private var pendingStart = false

    func hasPermission() -> Bool {
        AVAudioSession.sharedInstance().recordPermission == .granted
    }

    /// Starts recording immediately if permission is already granted, otherwise prompts first.
    func requestStart() {
        guard !isRecording else { return }
        switch AVAudioSession.sharedInstance().recordPermission {
        case .granted:
            start()
        case .undetermined:
            pendingStart = true
            AVAudioSession.sharedInstance().requestRecordPermission { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self, self.pendingStart else { return }
                    self.pendingStart = false
                    if granted { self.start() }
                }
            }
        case .denied:
            break
        @unknown default:
            break
        }
    }

    private func start() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("chat360_voice_\(Int(Date().timeIntervalSince1970 * 1000)).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 96_000,
        ]
        do {
            try AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try AVAudioSession.sharedInstance().setActive(true)
            let newRecorder = try AVAudioRecorder(url: url, settings: settings)
            newRecorder.isMeteringEnabled = true
            guard newRecorder.record() else { return }
            recorder = newRecorder
            outputURL = url
        } catch {
            return
        }
        amplitudes = []
        elapsedMs = 0
        startedAt = Date()
        isRecording = true
        timer = Timer.scheduledTimer(withTimeInterval: sampleIntervalSeconds, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func tick() {
        guard isRecording, let recorder, let startedAt else { return }
        elapsedMs = Int64(Date().timeIntervalSince(startedAt) * 1000)
        recorder.updateMeters()
        let level = amplitudeLevel(fromDb: recorder.averagePower(forChannel: 0))
        amplitudes = Array((amplitudes + [level]).suffix(maxSamples))
    }

    /// Converts `AVAudioRecorder`'s dBFS metering value to the 0-32767 scale `VoiceWaveformBars`
    /// expects.
    private func amplitudeLevel(fromDb db: Float) -> Int {
        guard db.isFinite else { return 0 }
        let minDb: Float = -60
        let clamped = max(db, minDb)
        let normalized = (clamped - minDb) / -minDb
        return Int(normalized * 32767)
    }

    /// Stops and returns the completed take, or nil if nothing was recorded/it failed.
    func stop() -> VoiceRecording? {
        guard isRecording else { return nil }
        isRecording = false
        timer?.invalidate()
        timer = nil
        let url = outputURL
        let capturedAmplitudes = amplitudes
        let capturedDuration = elapsedMs
        recorder?.stop()
        recorder = nil
        outputURL = nil
        guard let url,
              let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int,
              size > 0
        else {
            if let url { try? FileManager.default.removeItem(at: url) }
            return nil
        }
        return VoiceRecording(fileURL: url, amplitudes: capturedAmplitudes, durationMs: capturedDuration)
    }

    /// Stops (if needed) and discards the file entirely.
    func cancel() {
        timer?.invalidate()
        timer = nil
        if isRecording { recorder?.stop() }
        recorder = nil
        if let outputURL { try? FileManager.default.removeItem(at: outputURL) }
        outputURL = nil
        isRecording = false
        amplitudes = []
        elapsedMs = 0
    }
}
