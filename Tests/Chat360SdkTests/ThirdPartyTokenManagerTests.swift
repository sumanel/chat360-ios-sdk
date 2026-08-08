import XCTest
@testable import Chat360SDK

final class ThirdPartyTokenManagerTests: XCTestCase {

    func testFetchesATokenOnFirstUse() async throws {
        var fetchCount = 0
        let manager = ThirdPartyTokenManager(
            fetchToken: { fetchCount += 1; return TokenResponse(bearer_token: "token-1", expires_in: 3600) },
            now: { Date(timeIntervalSince1970: 0) }
        )

        let token = try await manager.validToken()

        XCTAssertEqual(token, "token-1")
        XCTAssertEqual(fetchCount, 1)
    }

    func testReusesTheCachedTokenWhileItHasNotExpired() async throws {
        var fetchCount = 0
        var now = Date(timeIntervalSince1970: 0)
        let manager = ThirdPartyTokenManager(
            fetchToken: { fetchCount += 1; return TokenResponse(bearer_token: "token-\(fetchCount)", expires_in: 3600) },
            now: { now }
        )

        _ = try await manager.validToken()
        now = now.addingTimeInterval(3_000) // well under the 3600s expiry
        let token = try await manager.validToken()

        XCTAssertEqual(token, "token-1")
        XCTAssertEqual(fetchCount, 1)
    }

    func testRefetchesOnceTheSafetyMarginBeforeExpiryHasPassed() async throws {
        var fetchCount = 0
        var now = Date(timeIntervalSince1970: 0)
        let manager = ThirdPartyTokenManager(
            fetchToken: { fetchCount += 1; return TokenResponse(bearer_token: "token-\(fetchCount)", expires_in: 3600) },
            now: { now }
        )

        _ = try await manager.validToken()
        // expiresAt = 3600 - 60 = 3540s; land exactly on/after that boundary.
        now = Date(timeIntervalSince1970: 3540)
        let token = try await manager.validToken()

        XCTAssertEqual(token, "token-2")
        XCTAssertEqual(fetchCount, 2)
    }

    func testInvalidateForcesTheNextCallToRefetchEvenIfNotExpired() async throws {
        var fetchCount = 0
        let manager = ThirdPartyTokenManager(
            fetchToken: { fetchCount += 1; return TokenResponse(bearer_token: "token-\(fetchCount)", expires_in: 3600) },
            now: { Date(timeIntervalSince1970: 0) }
        )

        _ = try await manager.validToken()
        await manager.invalidate()
        let token = try await manager.validToken()

        XCTAssertEqual(token, "token-2")
        XCTAssertEqual(fetchCount, 2)
    }

    func testConcurrentCallersOnlyTriggerOneFetch() async throws {
        actor Counter {
            var value = 0
            func increment() -> Int { value += 1; return value }
        }
        let counter = Counter()
        let manager = ThirdPartyTokenManager(
            fetchToken: {
                _ = await counter.increment()
                try await Task.sleep(nanoseconds: 50_000_000) // simulated network latency
                return TokenResponse(bearer_token: "token-1", expires_in: 3600)
            },
            now: { Date(timeIntervalSince1970: 0) }
        )

        let results = try await withThrowingTaskGroup(of: String.self) { group in
            for _ in 0..<20 { group.addTask { try await manager.validToken() } }
            var collected: [String] = []
            for try await value in group { collected.append(value) }
            return collected
        }

        XCTAssertEqual(results, Array(repeating: "token-1", count: 20))
        let fetchCount = await counter.value
        XCTAssertEqual(fetchCount, 1)
    }
}
