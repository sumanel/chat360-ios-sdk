import XCTest
import Speech
@testable import Chat360SDK

/// The dictation permission flow: every "not allowed" outcome must surface a message, and the message must be clearable.
@MainActor
final class SpeechToTextControllerTests: XCTestCase {

    private func controller(
        supported: Bool = true,
        status: SFSpeechRecognizerAuthorizationStatus,
        speechPrompt: SFSpeechRecognizerAuthorizationStatus = .denied,
        microphone: Bool = false
    ) -> SpeechToTextController {
        SpeechToTextController(
            recognizerAvailable: { _ in supported },
            authorizationStatus: { status },
            requestSpeechAuthorization: { $0(speechPrompt) },
            requestMicrophonePermission: { $0(microphone) }
        )
    }

    /// The permission callbacks hop back to the main actor in a Task, so let those run.
    private func settle() async {
        try? await Task.sleep(nanoseconds: 100_000_000)
    }

    func testDeniedSpeechStatusSetsErrorImmediately() {
        let stt = controller(status: .denied)
        stt.requestStart()
        XCTAssertEqual(stt.error, SpeechToTextController.permissionDeniedMessage)
        XCTAssertFalse(stt.isListening)
    }

    func testRestrictedSpeechStatusSetsError() {
        let stt = controller(status: .restricted)
        stt.requestStart()
        XCTAssertEqual(stt.error, SpeechToTextController.permissionDeniedMessage)
    }

    func testDecliningTheSpeechPromptSetsError() async {
        let stt = controller(status: .notDetermined, speechPrompt: .denied)
        stt.requestStart()
        await settle()
        XCTAssertEqual(stt.error, SpeechToTextController.permissionDeniedMessage)
        XCTAssertFalse(stt.isListening)
    }

    func testDeniedMicrophoneSetsErrorEvenWhenSpeechIsAuthorized() async {
        let stt = controller(status: .authorized, microphone: false)
        stt.requestStart()
        await settle()
        XCTAssertEqual(stt.error, SpeechToTextController.permissionDeniedMessage)
        XCTAssertFalse(stt.isListening)
    }

    func testDeniedMicrophoneAfterAcceptingSpeechPromptSetsError() async {
        let stt = controller(status: .notDetermined, speechPrompt: .authorized, microphone: false)
        stt.requestStart()
        await settle()
        XCTAssertEqual(stt.error, SpeechToTextController.permissionDeniedMessage)
    }

    func testUnsupportedRecognizerDoesNotPromptOrSetError() async {
        var prompted = false
        let stt = SpeechToTextController(
            recognizerAvailable: { _ in false },
            authorizationStatus: { .notDetermined },
            requestSpeechAuthorization: { prompted = true; $0(.authorized) },
            requestMicrophonePermission: { _ in prompted = true }
        )
        stt.requestStart()
        await settle()
        XCTAssertFalse(prompted)
        XCTAssertNil(stt.error)
    }

    func testDismissErrorClearsIt() {
        let stt = controller(status: .denied)
        stt.requestStart()
        XCTAssertNotNil(stt.error)
        stt.dismissError()
        XCTAssertNil(stt.error)
    }

    func testRequestingAgainClearsThePreviousError() {
        var supported = true
        let stt = SpeechToTextController(
            recognizerAvailable: { _ in supported },
            authorizationStatus: { .denied },
            requestSpeechAuthorization: { $0(.denied) },
            requestMicrophonePermission: { $0(false) }
        )
        stt.requestStart()
        XCTAssertNotNil(stt.error)
        // On the retry the recognizer is unavailable, so nothing new is reported - and the stale message must go.
        supported = false
        stt.requestStart()
        XCTAssertNil(stt.error)
    }
}
