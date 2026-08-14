import XCTest
@testable import Chat360SDK

final class ReconnectManagerTests: XCTestCase {
    func testScheduleReconnectDoublesBackoff() {
        let scheduler = FakeScheduler()
        var reconnectCount = 0
        let manager = ReconnectManager(scheduler: scheduler, baseDelayMs: 5_000, reconnect: { reconnectCount += 1 })

        manager.scheduleReconnect(suppress: false)
        XCTAssertEqual(scheduler.scheduled.last?.delayMs, 5_000)

        scheduler.fireNext()
        XCTAssertEqual(reconnectCount, 1)

        manager.scheduleReconnect(suppress: false)
        XCTAssertEqual(scheduler.scheduled.last?.delayMs, 10_000)
    }

    func testOnConnectedResetsBackoff() {
        let scheduler = FakeScheduler()
        let manager = ReconnectManager(scheduler: scheduler, baseDelayMs: 5_000, reconnect: {})

        manager.scheduleReconnect(suppress: false)
        scheduler.fireNext()
        manager.scheduleReconnect(suppress: false)
        XCTAssertEqual(scheduler.scheduled.last?.delayMs, 10_000)

        manager.onConnected()
        manager.scheduleReconnect(suppress: false)
        XCTAssertEqual(scheduler.scheduled.last?.delayMs, 5_000)
    }

    func testSuppressedReconnectDoesNotSchedule() {
        let scheduler = FakeScheduler()
        let manager = ReconnectManager(scheduler: scheduler, baseDelayMs: 5_000, reconnect: {})
        manager.scheduleReconnect(suppress: true)
        XCTAssertTrue(scheduler.scheduled.isEmpty)
    }
}
