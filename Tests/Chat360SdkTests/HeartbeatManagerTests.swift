import XCTest
@testable import Chat360SDK

final class HeartbeatManagerTests: XCTestCase {

    func testSlowCallbackFiresOnlyWhenNoPongArrivesWithinTheWaitWindow() {
        let scheduler = TestScheduler()
        var pingsSent = 0
        var slowStates: [Bool] = []
        let manager = HeartbeatManager(
            scheduler: scheduler,
            pingWaitingTimer: 2,
            sendPing: { pingsSent += 1 },
            onSlowConnectionChanged: { slowStates.append($0) }
        )

        manager.start()
        scheduler.advance(by: 2.001) // idle window elapses, ping sent
        XCTAssertEqual(pingsSent, 1)
        XCTAssertTrue(slowStates.isEmpty)

        scheduler.advance(by: 2.001) // no pong arrives within the wait window
        XCTAssertEqual(slowStates, [true])
    }

    func testAPongWithinTheWaitWindowCancelsTheSlowSignalForThatCycle() {
        let scheduler = TestScheduler()
        var pingsSent = 0
        var slowStates: [Bool] = []
        let manager = HeartbeatManager(
            scheduler: scheduler,
            pingWaitingTimer: 2,
            sendPing: { pingsSent += 1 },
            onSlowConnectionChanged: { slowStates.append($0) }
        )

        manager.start()
        scheduler.advance(by: 2.001) // ping sent
        XCTAssertEqual(pingsSent, 1)

        manager.onMessageReceived(isPong: true) // pong arrives in time
        scheduler.advance(by: 1) // well before the next cycle's ping is even due
        XCTAssertTrue(slowStates.isEmpty)
    }

    func testAnyInboundFrameReschedulesTheNextPingNotOnlyAPong() {
        let scheduler = TestScheduler()
        var pingsSent = 0
        let manager = HeartbeatManager(
            scheduler: scheduler,
            pingWaitingTimer: 2,
            sendPing: { pingsSent += 1 },
            onSlowConnectionChanged: { _ in }
        )

        manager.start()
        scheduler.advance(by: 1)
        manager.onMessageReceived(isPong: false) // a normal bot message resets the idle timer
        scheduler.advance(by: 1.999) // 1 + 1.999 = 2.999 since start, but only 1.999 since the reset
        XCTAssertEqual(pingsSent, 0)
        scheduler.advance(by: 0.002)
        XCTAssertEqual(pingsSent, 1)
    }
}
