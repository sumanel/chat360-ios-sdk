import XCTest
@testable import Chat360SDK

/// Thumbs down needs a reason (20+ characters); thumbs up asks for one too, but it is optional.
@available(iOS 16.0, *)
final class LikeFeedbackTests: XCTestCase {

    func testADislikeHasATwentyCharacterMinimum() {
        XCTAssertEqual(FeedbackDialogKind.dislike.minCharCount, 20)
    }

    func testALikeNeedsNoCharacters() {
        XCTAssertEqual(FeedbackDialogKind.like.minCharCount, 0)
    }

    func testTypedTextIsTrimmedBeforeItIsSent() {
        XCTAssertEqual(normalizedFeedbackRemarks("  Very helpful \n"), "Very helpful")
    }

    func testBlankTextIsSentAsNoRemarksAtAll() {
        XCTAssertNil(normalizedFeedbackRemarks(""))
        XCTAssertNil(normalizedFeedbackRemarks("   \n "))
    }
}
