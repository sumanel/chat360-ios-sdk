import XCTest
@testable import Chat360SDK

final class AckTrackerTests: XCTestCase {

    func testTimesOutAtExactlyAckTimeoutWithNoAck() {
        let scheduler = TestScheduler()
        var timedOutId: String?
        let tracker = AckTracker(scheduler: scheduler, ackTimeout: 10, onTimeout: { timedOutId = $0 })

        tracker.trackSend("msg-1")
        scheduler.advance(by: 9.999)
        XCTAssertNil(timedOutId)
        scheduler.advance(by: 0.002)
        XCTAssertEqual(timedOutId, "msg-1")
    }

    func testAcknowledgingBeforeTheTimeoutCancelsIt() {
        let scheduler = TestScheduler()
        var timedOutId: String?
        let tracker = AckTracker(scheduler: scheduler, ackTimeout: 10, onTimeout: { timedOutId = $0 })

        tracker.trackSend("msg-1")
        scheduler.advance(by: 5)
        tracker.acknowledge("msg-1")
        scheduler.advance(by: 10)
        XCTAssertNil(timedOutId)
    }

    func testEachChatMsgIdIsTrackedIndependently() {
        let scheduler = TestScheduler()
        var timedOut: [String] = []
        let tracker = AckTracker(scheduler: scheduler, ackTimeout: 10, onTimeout: { timedOut.append($0) })

        tracker.trackSend("msg-1")
        scheduler.advance(by: 4)
        tracker.trackSend("msg-2")
        tracker.acknowledge("msg-1")

        scheduler.advance(by: 6.001) // msg-1 acked; msg-2 still short of its own 10s window
        XCTAssertEqual(timedOut, [])

        scheduler.advance(by: 4) // msg-2 now past its 10s window
        XCTAssertEqual(timedOut, ["msg-2"])
    }
}
