import XCTest
@testable import Chat360SDK

final class HeartbeatManagerTests: XCTestCase {
    func testStartSchedulesPing() {
        let scheduler = FakeScheduler()
        var pingCount = 0
        let manager = HeartbeatManager(scheduler: scheduler, pingWaitingTimerMs: 2_000, sendPing: { pingCount += 1 }, onSlowConnectionChanged: { _ in })

        manager.start()
        scheduler.fireNext()
        XCTAssertEqual(pingCount, 1)
    }

    func testNoPongMarksSlowConnection() {
        let scheduler = FakeScheduler()
        var slowStates: [Bool] = []
        let manager = HeartbeatManager(scheduler: scheduler, pingWaitingTimerMs: 2_000, sendPing: {}, onSlowConnectionChanged: { slowStates.append($0) })

        manager.start()
        scheduler.fireNext()
        scheduler.fireNext()
        XCTAssertEqual(slowStates, [true])
    }

    func testPongClearsSlowState() {
        let scheduler = FakeScheduler()
        var slowStates: [Bool] = []
        let manager = HeartbeatManager(scheduler: scheduler, pingWaitingTimerMs: 2_000, sendPing: {}, onSlowConnectionChanged: { slowStates.append($0) })

        manager.start()
        scheduler.fireNext()
        scheduler.fireNext()
        XCTAssertEqual(slowStates, [true])

        manager.onMessageReceived(isPong: true)
        XCTAssertEqual(slowStates, [true, false])
    }

    func testStopCancelsScheduledPings() {
        let scheduler = FakeScheduler()
        var pingCount = 0
        let manager = HeartbeatManager(scheduler: scheduler, pingWaitingTimerMs: 2_000, sendPing: { pingCount += 1 }, onSlowConnectionChanged: { _ in })

        manager.start()
        manager.stop()
        scheduler.fireAll()
        XCTAssertEqual(pingCount, 0)
    }
}
