import Foundation
import Speech
import AVFoundation

@available(iOS 13.0, *)
@MainActor
public final class SpeechToTextController: NSObject, ObservableObject {
    @Published public private(set) var isListening = false
    @Published public private(set) var transcript = ""
    @Published public private(set) var error: String?

    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    private var language = Locale.current.identifier

    public override init() {
        super.init()
    }

    public func isSupported() -> Bool {
        SFSpeechRecognizer(locale: Locale(identifier: language))?.isAvailable ?? false
    }

    public func hasPermission() -> Bool {
        SFSpeechRecognizer.authorizationStatus() == .authorized
    }

    public func requestStart(languageTag: String = Locale.current.identifier) {
        if isListening { return }
        language = languageTag
        guard isSupported() else { return }
        if hasPermission() {
            start()
            return
        }
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            Task { @MainActor in
                if status == .authorized { self?.start() }
            }
        }
    }

    private func start() {
        transcript = ""
        error = nil
        recognizer = SFSpeechRecognizer(locale: Locale(identifier: language))

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            self.error = "Speech recognition error"
            return
        }

        let newRequest = SFSpeechAudioBufferRecognitionRequest()
        newRequest.shouldReportPartialResults = true
        request = newRequest

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            newRequest.append(buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            self.error = "Speech recognition error"
            return
        }

        isListening = true
        task = recognizer?.recognitionTask(with: newRequest) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }
                if let result {
                    self.transcript = result.bestTranscription.formattedString
                }
                if error != nil || (result?.isFinal ?? false) {
                    if self.isListening {
                        self.stopEngine()
                        self.start()
                    }
                }
            }
        }
    }

    private func stopEngine() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        task = nil
        request = nil
    }

    public func stop() {
        isListening = false
        stopEngine()
    }

    public func release() {
        isListening = false
        stopEngine()
    }
}
