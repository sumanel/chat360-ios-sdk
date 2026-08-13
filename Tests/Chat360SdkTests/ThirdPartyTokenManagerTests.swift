import XCTest
@testable import Chat360SDK

final class ThirdPartyTokenManagerTests: XCTestCase {
    func testFetchesATokenOnFirstUse() async throws {
        var fetchCount = 0
        let manager = ThirdPartyTokenManager(
            fetchToken: { fetchCount += 1; return TokenResponse(bearerToken: "token-1", expiresIn: 3600) },
            nowMillis: { 0 }
        )

        let token = try await manager.validToken()
        XCTAssertEqual(token, "token-1")
        XCTAssertEqual(fetchCount, 1)
    }

    func testReusesTheCachedTokenWhileNotExpired() async throws {
        var fetchCount = 0
        var now: Int64 = 0
        let manager = ThirdPartyTokenManager(
            fetchToken: { fetchCount += 1; return TokenResponse(bearerToken: "token-\(fetchCount)", expiresIn: 3600) },
            nowMillis: { now }
        )

        _ = try await manager.validToken()
        now += 3_000_000
        let token = try await manager.validToken()

        XCTAssertEqual(token, "token-1")
        XCTAssertEqual(fetchCount, 1)
    }

    func testRefetchesOnceTheSafetyMarginBeforeExpiryHasPassed() async throws {
        var fetchCount = 0
        var now: Int64 = 0
        let manager = ThirdPartyTokenManager(
            fetchToken: { fetchCount += 1; return TokenResponse(bearerToken: "token-\(fetchCount)", expiresIn: 3600) },
            nowMillis: { now }
        )

        _ = try await manager.validToken()
        now = 3_540_000
        let token = try await manager.validToken()

        XCTAssertEqual(token, "token-2")
        XCTAssertEqual(fetchCount, 2)
    }

    func testInvalidateForcesTheNextCallToRefetchEvenIfNotExpired() async throws {
        var fetchCount = 0
        let manager = ThirdPartyTokenManager(
            fetchToken: { fetchCount += 1; return TokenResponse(bearerToken: "token-\(fetchCount)", expiresIn: 3600) },
            nowMillis: { 0 }
        )

        _ = try await manager.validToken()
        await manager.invalidate()
        let token = try await manager.validToken()

        XCTAssertEqual(token, "token-2")
        XCTAssertEqual(fetchCount, 2)
    }

    func testConcurrentCallersOnlyTriggerOneFetch() async throws {
        let manager = ThirdPartyTokenManager(
            fetchToken: {
                try await Task.sleep(nanoseconds: 50_000_000)
                return TokenResponse(bearerToken: "token-1", expiresIn: 3600)
            },
            nowMillis: { 0 }
        )

        let results = try await withThrowingTaskGroup(of: String.self) { group in
            for _ in 0..<20 {
                group.addTask { try await manager.validToken() }
            }
            var collected: [String] = []
            for try await value in group { collected.append(value) }
            return collected
        }

        XCTAssertTrue(results.allSatisfy { $0 == "token-1" })
    }
}
