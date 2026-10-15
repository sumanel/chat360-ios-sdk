import XCTest
@testable import Chat360SDK

/// A dislike is final: once a message is disliked it can be neither liked nor un-disliked.
final class ReactionTapTests: XCTestCase {

    func testAnUnratedMessageOpensTheLikePopupOnThumbsUp() {
        XCTAssertEqual(ReactionTap.likeTap(current: nil), .openLikePopup)
    }

    func testAnUnratedMessageOpensTheDislikePopupOnThumbsDown() {
        XCTAssertEqual(ReactionTap.dislikeTap(current: nil), .openDislikePopup)
    }

    func testAfterADislikeThumbsUpDoesNothing() {
        XCTAssertEqual(ReactionTap.likeTap(current: false), .ignore)
    }

    func testAfterADislikeTappingThumbsDownAgainDoesNothing() {
        XCTAssertEqual(ReactionTap.dislikeTap(current: false), .ignore)
    }

    func testALikedMessageIgnoresAnotherThumbsUp() {
        XCTAssertEqual(ReactionTap.likeTap(current: true), .ignore)
    }

    func testALikedMessageCanBeChangedToADislikeWhichThenAsksForItsReason() {
        XCTAssertEqual(ReactionTap.dislikeTap(current: true), .openDislikePopup)
    }

    func testDislikeThenLikeThenDislikeChangesNothing() {
        var rating: Bool? = nil
        func apply(_ tap: ReactionTap, _ newRating: Bool) { if tap != .ignore { rating = newRating } }
        apply(ReactionTap.dislikeTap(current: rating), false)
        apply(ReactionTap.likeTap(current: rating), true)
        apply(ReactionTap.dislikeTap(current: rating), false)
        apply(ReactionTap.likeTap(current: rating), true)
        XCTAssertEqual(rating, false, "still disliked")
    }
}
