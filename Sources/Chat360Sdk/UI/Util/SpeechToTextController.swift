import Foundation
import Speech
import AVFoundation

/// Continuous dictation via `SFSpeechRecognizer` - mirrors the widget's Web Speech API usage:
/// a single running `transcript` updates as the user talks. Unlike Android's `SpeechRecognizer`
/// (which completes after each utterance and has to be manually restarted), iOS's recognition
/// task stays open across pauses on its own, so there's no per-utterance restart loop needed here.
@MainActor
final class SpeechToTextController: NSObject, ObservableObject {
    @Published private(set) var isListening = false
    @Published private(set) var transcript = ""
    @Published private(set) var error: String?

    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    private var pendingStart = false

    func isSupported() -> Bool {
        (SFSpeechRecognizer() ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US")))?.isAvailable ?? false
    }

    func hasPermission() -> Bool {
        SFSpeechRecognizer.authorizationStatus() == .authorized && AVAudioSession.sharedInstance().recordPermission == .granted
    }

    /// Starts listening immediately if permission is already granted, otherwise prompts first.
    func requestStart() {
        guard !isListening, isSupported() else { return }
        if hasPermission() {
            start()
            return
        }
        pendingStart = true
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                DispatchQueue.main.async {
                    guard let self, self.pendingStart else { return }
                    self.pendingStart = false
                    if status == .authorized, granted { self.start() }
                }
            }
        }
    }

    private func start() {
        transcript = ""
        error = nil

        guard let recognizer = SFSpeechRecognizer(), recognizer.isAvailable else {
            error = "Speech recognition error"
            return
        }
        self.recognizer = recognizer

        do {
            try AVAudioSession.sharedInstance().setCategory(.record, mode: .measurement, options: .duckOthers)
            try AVAudioSession.sharedInstance().setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            self.error = "Speech recognition error"
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        self.request = request

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            request.append(buffer)
        }
        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            self.error = "Speech recognition error"
            return
        }

        isListening = true
        task = recognizer.recognitionTask(with: request) { [weak self] result, taskError in
            Task { @MainActor in
                guard let self else { return }
                if let result {
                    self.transcript = result.bestTranscription.formattedString
                }
                if taskError != nil, self.isListening {
                    self.error = "Speech recognition error"
                    self.isListening = false
                    self.stopEngine()
                }
            }
        }
    }

    /// Ends dictation - the accumulated `transcript` is left for the caller to keep or discard.
    func stop() {
        isListening = false
        stopEngine()
        task?.finish()
    }

    func release() {
        isListening = false
        stopEngine()
        task?.cancel()
        task = nil
    }

    private func stopEngine() {
        if audioEngine.isRunning { audioEngine.stop() }
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
    }
}
