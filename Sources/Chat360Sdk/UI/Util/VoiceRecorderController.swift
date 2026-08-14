import Foundation
import AVFoundation

public struct VoiceRecording {
    public let fileURL: URL
    public let amplitudes: [Int]
    public let durationMs: Int64

    public init(fileURL: URL, amplitudes: [Int], durationMs: Int64) {
        self.fileURL = fileURL
        self.amplitudes = amplitudes
        self.durationMs = durationMs
    }
}

@available(iOS 13.0, *)
@MainActor
public final class VoiceRecorderController: NSObject, ObservableObject, AVAudioRecorderDelegate {
    private static let sampleIntervalMs: Int64 = 100
    private static let maxSamples = 60

    @Published public private(set) var isRecording = false
    @Published public private(set) var amplitudes: [Int] = []
    @Published public private(set) var elapsedMs: Int64 = 0

    private var recorder: AVAudioRecorder?
    private var outputURL: URL?
    private var startedAt: Date?
    private var ticker: Timer?

    public override init() {
        super.init()
    }

    public func hasPermission() -> Bool {
        if #available(iOS 17.0, *) {
            return AVAudioApplication.shared.recordPermission == .granted
        }
        return AVAudioSession.sharedInstance().recordPermission == .granted
    }

    public func requestStart() {
        if isRecording { return }
        if hasPermission() {
            start()
            return
        }
        if #available(iOS 17.0, *) {
            AVAudioApplication.requestRecordPermission { [weak self] granted in
                Task { @MainActor in
                    if granted { self?.start() }
                }
            }
        } else {
            AVAudioSession.sharedInstance().requestRecordPermission { [weak self] granted in
                Task { @MainActor in
                    if granted { self?.start() }
                }
            }
        }
    }

    private func start() {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("chat360_voice_\(Int64(Date().timeIntervalSince1970 * 1000)).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 96_000,
        ]
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default)
            try session.setActive(true)
            let newRecorder = try AVAudioRecorder(url: file, settings: settings)
            newRecorder.delegate = self
            newRecorder.isMeteringEnabled = true
            guard newRecorder.record() else { return }
            recorder = newRecorder
        } catch {
            return
        }
        outputURL = file
        amplitudes = []
        elapsedMs = 0
        startedAt = Date()
        isRecording = true
        ticker?.invalidate()
        ticker = Timer.scheduledTimer(withTimeInterval: Double(Self.sampleIntervalMs) / 1000, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func tick() {
        guard isRecording, let startedAt else { return }
        elapsedMs = Int64(Date().timeIntervalSince(startedAt) * 1000)
        recorder?.updateMeters()
        let power = recorder?.averagePower(forChannel: 0) ?? -160
        let level = Int(max(0, (power + 160) / 160 * 32767))
        amplitudes = Array((amplitudes + [level]).suffix(Self.maxSamples))
    }

    @discardableResult
    public func stop() -> VoiceRecording? {
        guard isRecording else { return nil }
        isRecording = false
        ticker?.invalidate()
        ticker = nil
        let file = outputURL
        let capturedAmplitudes = amplitudes
        let capturedDuration = elapsedMs
        recorder?.stop()
        recorder = nil
        outputURL = nil
        guard let file, FileManager.default.fileExists(atPath: file.path),
              let attributes = try? FileManager.default.attributesOfItem(atPath: file.path),
              let size = attributes[.size] as? Int, size > 0 else {
            if let file { try? FileManager.default.removeItem(at: file) }
            return nil
        }
        return VoiceRecording(fileURL: file, amplitudes: capturedAmplitudes, durationMs: capturedDuration)
    }

    public func cancel() {
        ticker?.invalidate()
        ticker = nil
        if isRecording {
            recorder?.stop()
            recorder = nil
        }
        if let outputURL { try? FileManager.default.removeItem(at: outputURL) }
        outputURL = nil
        isRecording = false
        amplitudes = []
        elapsedMs = 0
    }
}
