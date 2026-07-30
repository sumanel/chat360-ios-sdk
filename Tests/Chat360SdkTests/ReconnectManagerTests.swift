import XCTest
@testable import Chat360SDK

final class ReconnectManagerTests: XCTestCase {

    func testDelayDoublesOnEachSuccessiveScheduledAttempt() {
        let scheduler = TestScheduler()
        var reconnectCount = 0
        let manager = ReconnectManager(scheduler: scheduler, baseDelay: 1, reconnect: { reconnectCount += 1 })

        manager.scheduleReconnect(suppress: false) // delay = 1 * 1
        scheduler.advance(by: 1.001)
        XCTAssertEqual(reconnectCount, 1)

        manager.scheduleReconnect(suppress: false) // delay = 1 * 2
        scheduler.advance(by: 1.999)
        XCTAssertEqual(reconnectCount, 1)
        scheduler.advance(by: 0.002)
        XCTAssertEqual(reconnectCount, 2)

        manager.scheduleReconnect(suppress: false) // delay = 1 * 4
        scheduler.advance(by: 3.999)
        XCTAssertEqual(reconnectCount, 2)
        scheduler.advance(by: 0.002)
        XCTAssertEqual(reconnectCount, 3)
    }

    func testOnConnectedResetsTheIntervalBackTo1() {
        let scheduler = TestScheduler()
        var reconnectCount = 0
        let manager = ReconnectManager(scheduler: scheduler, baseDelay: 1, reconnect: { reconnectCount += 1 })

        manager.scheduleReconnect(suppress: false) // delay = 1 * 1
        scheduler.advance(by: 1.001)
        XCTAssertEqual(reconnectCount, 1)

        manager.onConnected()

        manager.scheduleReconnect(suppress: false) // back to base delay, not doubled
        scheduler.advance(by: 0.999)
        XCTAssertEqual(reconnectCount, 1)
        scheduler.advance(by: 0.002)
        XCTAssertEqual(reconnectCount, 2)
    }

    func testSuppressPreventsSchedulingEntirely() {
        let scheduler = TestScheduler()
        var reconnectCount = 0
        let manager = ReconnectManager(scheduler: scheduler, baseDelay: 1, reconnect: { reconnectCount += 1 })

        manager.scheduleReconnect(suppress: true)
        scheduler.advance(by: 10)
        XCTAssertEqual(reconnectCount, 0)
    }
}
