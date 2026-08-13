import XCTest
@testable import Chat360SDK

final class AckTrackerTests: XCTestCase {
    func testAcknowledgeCancelsTimer() {
        let scheduler = FakeScheduler()
        var timedOut: [String] = []
        let tracker = AckTracker(scheduler: scheduler, retryDelaysMs: [100, 200], onTimeout: { timedOut.append($0) })

        var resendCount = 0
        tracker.trackSend(chatMsgId: "msg1", resend: { resendCount += 1 })
        tracker.acknowledge(chatMsgId: "msg1")

        scheduler.fireAll()
        XCTAssertEqual(resendCount, 0)
        XCTAssertTrue(timedOut.isEmpty)
    }

    func testUnacknowledgedSendRetriesThenTimesOut() {
        let scheduler = FakeScheduler()
        var timedOut: [String] = []
        let tracker = AckTracker(scheduler: scheduler, retryDelaysMs: [100, 200], onTimeout: { timedOut.append($0) })

        var resendCount = 0
        tracker.trackSend(chatMsgId: "msg1", resend: { resendCount += 1 })

        scheduler.fireNext()
        XCTAssertEqual(resendCount, 1)
        scheduler.fireNext()
        XCTAssertEqual(resendCount, 2)
        scheduler.fireNext()
        XCTAssertEqual(timedOut, ["msg1"])
    }

    func testCancelAllStopsAllTracking() {
        let scheduler = FakeScheduler()
        var timedOut: [String] = []
        let tracker = AckTracker(scheduler: scheduler, retryDelaysMs: [100], onTimeout: { timedOut.append($0) })

        tracker.trackSend(chatMsgId: "a", resend: {})
        tracker.trackSend(chatMsgId: "b", resend: {})
        tracker.cancelAll()

        scheduler.fireAll()
        XCTAssertTrue(timedOut.isEmpty)
    }
}
