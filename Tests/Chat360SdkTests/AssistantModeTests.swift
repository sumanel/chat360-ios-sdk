import XCTest
@testable import Chat360SDK

/// The selected Assistant Mode option's variables (e.g. `agent_role`) ride along in session-init's `meta`.
final class AssistantModeTests: XCTestCase {

    private let roles = [
        Chat360AssistantModeOption(label: "Training", variables: ["agent_role": "training"]),
        Chat360AssistantModeOption(label: "Customer", variables: ["agent_role": "customer"]),
    ]

    // MARK: config

    func testDefaultSelectionIsTheSecondButtonAndSendsNothingUntilConfigured() {
        let features = Chat360FeatureConfig()
        XCTAssertEqual(features.initialAssistantModeIndex, 1)
        XCTAssertEqual(features.initialAssistantVariables, [:])
    }

    func testBothButtonsAreEnabledByDefault() {
        XCTAssertTrue(Chat360FeatureConfig().assistantModes.allSatisfy { $0.enabled })
    }

    func testSelectedOptionsVariablesSeedTheSessionMeta() {
        var features = Chat360FeatureConfig(assistantModes: roles, defaultAssistantMode: 0)
        XCTAssertEqual(features.initialAssistantVariables, ["agent_role": "training"])
        features.defaultAssistantMode = 1
        XCTAssertEqual(features.initialAssistantVariables, ["agent_role": "customer"])
    }

    func testNothingIsSentWhenTheSwitcherIsHidden() {
        let features = Chat360FeatureConfig(showAssistantMode: false, assistantModes: roles)
        XCTAssertEqual(features.initialAssistantVariables, [:])
    }

    func testOutOfRangeDefaultIsClampedInsteadOfCrashing() {
        XCTAssertEqual(Chat360FeatureConfig(assistantModes: roles, defaultAssistantMode: 9).initialAssistantModeIndex, 1)
        XCTAssertEqual(Chat360FeatureConfig(assistantModes: roles, defaultAssistantMode: -3).initialAssistantModeIndex, 0)
        let empty = Chat360FeatureConfig(assistantModes: [])
        XCTAssertEqual(empty.initialAssistantModeIndex, 0)
        XCTAssertEqual(empty.initialAssistantVariables, [:])
    }

    func testNoMoreThanTwoButtonsAreEverShown() {
        let three = roles + [Chat360AssistantModeOption(label: "Third", variables: ["agent_role": "third"])]
        let features = Chat360FeatureConfig(assistantModes: three)
        XCTAssertEqual(features.effectiveAssistantModes.map { $0.label }, ["Training", "Customer"])
        XCTAssertEqual(Chat360FeatureConfig.maxAssistantModes, 2)
    }

    func testADefaultPointingAtADroppedThirdButtonFallsBackToTheLastShownOne() {
        let three = roles + [Chat360AssistantModeOption(label: "Third", variables: ["agent_role": "third"])]
        let features = Chat360FeatureConfig(showAssistantMode: true, assistantModes: three, defaultAssistantMode: 2)
        XCTAssertEqual(features.initialAssistantModeIndex, 1)
        XCTAssertEqual(features.initialAssistantVariables, ["agent_role": "customer"])
    }

    // MARK: a room's role maps to a button

    func testARoomRoleMapsToTheButtonThatSendsIt() {
        let features = Chat360FeatureConfig(assistantModes: roles)
        XCTAssertEqual(features.assistantModeIndex(forRole: "training"), 0)
        XCTAssertEqual(features.assistantModeIndex(forRole: "customer"), 1)
    }

    func testAnUnknownOrMissingRoleMapsToNoButton() {
        let features = Chat360FeatureConfig(assistantModes: roles)
        XCTAssertNil(features.assistantModeIndex(forRole: "trainer"))
        XCTAssertNil(features.assistantModeIndex(forRole: nil))
    }

    func testARoleOnlyMatchesOnTheAgentRoleVariable() {
        let features = Chat360FeatureConfig(assistantModes: [Chat360AssistantModeOption(label: "A", variables: ["other": "training"]), roles[1]])
        XCTAssertNil(features.assistantModeIndex(forRole: "training"))
    }

    func testARoleMatchesIgnoringCaseAndSurroundingSpaces() {
        let features = Chat360FeatureConfig(assistantModes: roles)
        XCTAssertEqual(features.assistantModeIndex(forRole: "Training"), 0)
        XCTAssertEqual(features.assistantModeIndex(forRole: "  CUSTOMER "), 1)
        XCTAssertNil(features.assistantModeIndex(forRole: "   "))
    }

    func testAMatchingRoleBadgesAsItsButtonWithTheButtonsLabel() {
        XCTAssertEqual(roles.badge(forRole: "training"), Chat360AssistantRoleBadge(modeIndex: 0, label: "Training"))
        XCTAssertEqual(roles.badge(forRole: " Customer "), Chat360AssistantRoleBadge(modeIndex: 1, label: "Customer"))
    }

    func testARoleNoButtonSendsBadgesAsGenericWithItsOwnText() {
        XCTAssertEqual(roles.badge(forRole: " trainer "), Chat360AssistantRoleBadge(modeIndex: nil, label: "trainer"))
    }

    func testAMissingOrBlankRoleHasNoBadge() {
        XCTAssertNil(roles.badge(forRole: nil))
        XCTAssertNil(roles.badge(forRole: ""))
        XCTAssertNil(roles.badge(forRole: "   "))
    }

    func testAButtonDroppedByTheTwoButtonCapNeverMatches() {
        let three = roles + [Chat360AssistantModeOption(label: "Third", variables: ["agent_role": "third"])]
        XCTAssertNil(Chat360FeatureConfig(assistantModes: three).assistantModeIndex(forRole: "third"))
    }

    // MARK: merged meta

    private func repository(meta: [String: String]?, variables: [String: String]) -> ChatRepository {
        ChatRepository(baseUrl: "https://example.invalid", botId: "bot-1", meta: meta, assistantVariables: variables)
    }

    func testInitialVariablesAreMergedIntoHostMeta() {
        let repo = repository(meta: ["dealer_id": "W4300"], variables: ["agent_role": "customer"])
        XCTAssertEqual(repo.sessionMeta(resuming: false), ["dealer_id": "W4300", "agent_role": "customer"])
    }

    func testVariablesAloneAreSentWhenTheHostSetNoMeta() {
        XCTAssertEqual(repository(meta: nil, variables: ["agent_role": "training"]).sessionMeta(resuming: false), ["agent_role": "training"])
    }

    func testNoMetaAtAllWhenThereIsNeither() {
        XCTAssertNil(repository(meta: nil, variables: [:]).sessionMeta(resuming: false))
        XCTAssertNil(repository(meta: [:], variables: [:]).sessionMeta(resuming: false))
    }

    func testAnAssistantVariableWinsOverAHostMetaKeyOfTheSameName() {
        let repo = repository(meta: ["agent_role": "host"], variables: ["agent_role": "customer"])
        XCTAssertEqual(repo.sessionMeta(resuming: false), ["agent_role": "customer"])
    }

    func testSwitchingTheOptionChangesTheMetaForTheNextSession() {
        let repo = repository(meta: ["dealer_id": "W4300"], variables: ["agent_role": "customer"])
        repo.setAssistantVariables(["agent_role": "training"])
        XCTAssertEqual(repo.sessionMeta(resuming: false), ["dealer_id": "W4300", "agent_role": "training"])
    }

    // MARK: resuming a session never re-sends the variables

    func testResumingASessionSendsOnlyTheHostMeta() {
        let repo = repository(meta: ["dealer_id": "W4300"], variables: ["agent_role": "customer"])
        XCTAssertEqual(repo.sessionMeta(resuming: true), ["dealer_id": "W4300"])
    }

    func testResumingSendsNothingWhenThereIsOnlyAVariable() {
        XCTAssertNil(repository(meta: nil, variables: ["agent_role": "customer"]).sessionMeta(resuming: true))
    }

    func testResumingIgnoresAVariableEvenAfterTheSelectionChanged() {
        let repo = repository(meta: nil, variables: ["agent_role": "customer"])
        repo.setAssistantVariables(["agent_role": "training"])
        XCTAssertNil(repo.sessionMeta(resuming: true))
        XCTAssertEqual(repo.sessionMeta(resuming: false), ["agent_role": "training"])
    }
}
