import XCTest
@testable import Chat360SDK

final class ChatIdentityGuardTests: XCTestCase {
    private var defaults: UserDefaults!
    private var sessionDefaults: UserDefaults!
    private var cleared: [String] = []

    override func setUp() {
        defaults = UserDefaults(suiteName: "test_identity_\(UUID().uuidString)")!
        sessionDefaults = UserDefaults(suiteName: "test_session_\(UUID().uuidString)")!
        cleared = []
    }

    private func makeGuard() -> ChatIdentityGuard {
        ChatIdentityGuard(
            defaults: defaults,
            sessionStore: UserDefaultsSessionStore(defaults: sessionDefaults),
            roleStore: UserDefaultsRoomRoleStore(defaults: sessionDefaults),
            clearCache: { self.cleared.append($0) }
        )
    }

    func testFirstOpenWithUserClearsLegacyData() {
        XCTAssertTrue(makeGuard().apply(botId: "bot", endUserId: "EMP1"))
        XCTAssertEqual(cleared, ["bot"])
    }

    func testFirstOpenWithoutUserKeepsData() {
        XCTAssertFalse(makeGuard().apply(botId: "bot", endUserId: nil))
        XCTAssertTrue(cleared.isEmpty)
    }

    func testSameUserKeepsDataAndDifferentUserClears() {
        let g = makeGuard()
        g.apply(botId: "bot", endUserId: "EMP1")
        cleared = []
        XCTAssertFalse(g.apply(botId: "bot", endUserId: " EMP1 "))
        XCTAssertTrue(cleared.isEmpty)
        XCTAssertTrue(g.apply(botId: "bot", endUserId: "EMP2"))
        XCTAssertEqual(cleared, ["bot"])
    }

    func testDifferentUserDropsSavedSessionAndRoles() {
        let sessions = UserDefaultsSessionStore(defaults: sessionDefaults)
        let roles = UserDefaultsRoomRoleStore(defaults: sessionDefaults)
        let g = makeGuard()
        g.apply(botId: "bot", endUserId: "EMP1")
        sessions.save(botId: "bot", session: PersistedSession(roomId: "r1", sessionToken: "t", ownerId: "o"))
        roles.save(botId: "bot", roles: ["r1": "customer"])
        g.apply(botId: "bot", endUserId: "EMP2")
        XCTAssertNil(sessions.load(botId: "bot"))
        XCTAssertNil(sessions.loadForRoom(botId: "bot", roomId: "r1"))
        XCTAssertTrue(roles.load(botId: "bot").isEmpty)
    }

    func testResetClearsAndForgetsUser() {
        let g = makeGuard()
        g.apply(botId: "bot", endUserId: "EMP1")
        cleared = []
        g.reset(botId: "bot")
        XCTAssertEqual(cleared, ["bot"])
        XCTAssertTrue(g.apply(botId: "bot", endUserId: "EMP1"))
    }
}
