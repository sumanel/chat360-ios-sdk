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

    // A timer that was already running when the ack arrived still executes (cancelling only stops
    // timers that haven't started). It used to resend anyway and re-arm itself, resurrecting the
    // retry chain of a message the server had already acknowledged.
    func testATimerAlreadyRunningWhenTheAckArrivesDoesNotResendOrRearm() {
        let scheduler = FakeScheduler()
        var timedOut: [String] = []
        let tracker = AckTracker(scheduler: scheduler, retryDelaysMs: [100, 200], onTimeout: { timedOut.append($0) })
        var resendCount = 0
        tracker.trackSend(chatMsgId: "msg1", resend: { resendCount += 1 })
        let alreadyRunning = scheduler.scheduled[0].action

        tracker.acknowledge(chatMsgId: "msg1")
        alreadyRunning()

        XCTAssertEqual(resendCount, 0, "resent a message that was already acknowledged")
        XCTAssertTrue(scheduler.scheduled.isEmpty || scheduler.scheduled.dropFirst().isEmpty, "re-armed a retry for an acknowledged message")
        scheduler.fireAll()
        XCTAssertTrue(timedOut.isEmpty)
    }

    func testTheLastResendRacingWithAnAckDoesNotReportATimeout() {
        let scheduler = FakeScheduler()
        var timedOut: [String] = []
        let tracker = AckTracker(scheduler: scheduler, retryDelaysMs: [100], onTimeout: { timedOut.append($0) })
        tracker.trackSend(chatMsgId: "msg1", resend: {
            // The ack lands while the final resend is going out.
            tracker.acknowledge(chatMsgId: "msg1")
        })

        scheduler.fireAll()

        XCTAssertTrue(timedOut.isEmpty, "timed out a message that was acknowledged")
    }

    // Mirrors production threading: sends/retries on the main thread, timer callbacks on the
    // repository queue, acks on the socket's delegate queue, cancelAll from the session pool.
    // Run under Thread Sanitizer this fails on an unguarded dictionary; without it, it still
    // hammers the same paths so a regression tends to crash outright.
    func testHammeringFromEveryThreadTheProductionCodeUsesIsSafe() {
        let repoQueue = DispatchQueue(label: "com.chat360.sdk.repository")
        let tracker = AckTracker(scheduler: DispatchQueueScheduler(queue: repoQueue), retryDelaysMs: [1, 1, 1], onTimeout: { _ in })
        let urlQueue = DispatchQueue(label: "urlsession")
        let pool = DispatchQueue(label: "pool", attributes: .concurrent)
        let done = expectation(description: "done")
        let group = DispatchGroup()
        for i in 0..<300 {
            group.enter(); DispatchQueue.main.async { tracker.trackSend(chatMsgId: "m\(i)", resend: {}); group.leave() }
            group.enter(); urlQueue.async { tracker.acknowledge(chatMsgId: "m\(i / 2)"); group.leave() }
            if i % 50 == 0 { group.enter(); pool.async { tracker.cancelAll(); group.leave() } }
        }
        group.notify(queue: .main) { done.fulfill() }
        wait(for: [done], timeout: 20)
        // Let the 1ms timers drain on the repository queue while acks and cancels are still landing.
        let drained = expectation(description: "drained")
        repoQueue.asyncAfter(deadline: .now() + 0.3) { drained.fulfill() }
        wait(for: [drained], timeout: 5)
    }
}
