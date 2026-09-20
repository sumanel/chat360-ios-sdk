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
    // Text from earlier recognition sessions; iOS ends a session on pauses, so each restart
    // appends to this instead of wiping what was already said.
    private var finalizedText = ""

    // System permission/availability lookups, injectable so the permission flow can be unit tested.
    private let recognizerAvailable: (String) -> Bool
    private let authorizationStatus: () -> SFSpeechRecognizerAuthorizationStatus
    private let requestSpeechAuthorization: (@escaping (SFSpeechRecognizerAuthorizationStatus) -> Void) -> Void
    private let requestMicrophonePermission: (@escaping (Bool) -> Void) -> Void

    public static let permissionDeniedMessage = "Speech recognition needs microphone and speech access. Enable both in Settings."

    public override init() {
        recognizerAvailable = { SFSpeechRecognizer(locale: Locale(identifier: $0))?.isAvailable ?? false }
        authorizationStatus = { SFSpeechRecognizer.authorizationStatus() }
        requestSpeechAuthorization = { SFSpeechRecognizer.requestAuthorization($0) }
        requestMicrophonePermission = { AVAudioSession.sharedInstance().requestRecordPermission($0) }
        super.init()
    }

    init(
        recognizerAvailable: @escaping (String) -> Bool,
        authorizationStatus: @escaping () -> SFSpeechRecognizerAuthorizationStatus,
        requestSpeechAuthorization: @escaping (@escaping (SFSpeechRecognizerAuthorizationStatus) -> Void) -> Void,
        requestMicrophonePermission: @escaping (@escaping (Bool) -> Void) -> Void
    ) {
        self.recognizerAvailable = recognizerAvailable
        self.authorizationStatus = authorizationStatus
        self.requestSpeechAuthorization = requestSpeechAuthorization
        self.requestMicrophonePermission = requestMicrophonePermission
        super.init()
    }

    public func dismissError() { error = nil }

    public func isSupported() -> Bool {
        recognizerAvailable(language)
    }

    public func hasPermission() -> Bool {
        authorizationStatus() == .authorized
    }

    public func requestStart(languageTag: String = Locale.current.identifier) {
        if isListening { return }
        language = languageTag
        error = nil
        guard isSupported() else { return }
        switch authorizationStatus() {
        case .authorized:
            requestMicrophoneThenStart()
        case .notDetermined:
            requestSpeechAuthorization { [weak self] status in
                Task { @MainActor in
                    if status == .authorized {
                        self?.requestMicrophoneThenStart()
                    } else {
                        self?.error = Self.permissionDeniedMessage
                    }
                }
            }
        default:
            error = Self.permissionDeniedMessage
        }
    }

    // Speech recognition also needs the microphone; without it the audio engine yields no audio.
    private func requestMicrophoneThenStart() {
        requestMicrophonePermission { [weak self] granted in
            Task { @MainActor in
                if granted {
                    self?.start()
                } else {
                    self?.error = Self.permissionDeniedMessage
                }
            }
        }
    }

    private func start(resetting: Bool = true) {
        if resetting {
            finalizedText = ""
            transcript = ""
        }
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
                // Ignore callbacks from a superseded session (cancelling one fires an error callback).
                guard let self, self.request === newRequest else { return }
                if let result {
                    self.transcript = [self.finalizedText, result.bestTranscription.formattedString]
                        .filter { !$0.isEmpty }.joined(separator: " ")
                }
                if error != nil || (result?.isFinal ?? false) {
                    if self.isListening {
                        self.finalizedText = self.transcript
                        self.stopEngine()
                        self.start(resetting: false)
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
