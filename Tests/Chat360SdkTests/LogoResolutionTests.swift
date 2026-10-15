import XCTest
@testable import Chat360SDK

/// The host's configured logo (Hyundai's) is what shows. The server's appearance logo (the Chat360 one, for a bot with
/// no custom avatar) must never replace it - not on first load, and not after a dropped socket or a sleep/wake reload.
@available(iOS 13.0, *)
final class LogoResolutionTests: XCTestCase {
    private let hyundai = Chat360Logo.resource(light: "HyundaiLogo", dark: "HyundaiLogoDark")
    private let chat360 = Chat360Logo.remote(url: "https://cdn.example/chat360.png")
    private let other = Chat360Logo.remote(url: "https://cdn.example/other.png")

    private func appearance(avatar: String?) -> BotAppearanceDetails {
        BotAppearanceDetails(chatboxHeader: BotAppearanceDetails.ChatboxHeader(chatboxAvatar: avatar))
    }

    // MARK: - config beats server

    func testTheConfiguredLogoWinsOverTheServersLogo() {
        XCTAssertEqual(resolveLogo(configured: hyundai, fromServer: chat360), hyundai)
    }

    func testTheServersLogoOnlyFillsInWhenNothingIsConfigured() {
        XCTAssertEqual(resolveLogo(configured: nil, fromServer: chat360), chat360)
    }

    func testNoLogoAnywhereStaysNone() {
        XCTAssertNil(resolveLogo(configured: nil, fromServer: nil))
    }

    // MARK: - a reload never wipes a logo that is already there

    func testASuccessfulAppearanceLoadRecordsTheServersLogo() {
        var state = ChatUiState()
        state.applyAppearance(appearance(avatar: "https://cdn.example/chat360.png"), chatboxName: nil)
        XCTAssertEqual(state.logoOverride, chat360)
    }

    func testAFailedAppearanceReloadKeepsTheLastLogo() {
        var state = ChatUiState()
        state.applyAppearance(appearance(avatar: "https://cdn.example/chat360.png"), chatboxName: nil)
        state.applyAppearance(nil, chatboxName: nil) // the fetch failed after a reconnect
        XCTAssertEqual(state.logoOverride, chat360)
    }

    func testAReloadWithoutALogoKeepsTheLastLogo() {
        var state = ChatUiState()
        state.applyAppearance(appearance(avatar: "https://cdn.example/other.png"), chatboxName: nil)
        state.applyAppearance(appearance(avatar: nil), chatboxName: nil)
        XCTAssertEqual(state.logoOverride, other)
    }

    func testAReloadWithANewLogoReplacesTheOldOne() {
        var state = ChatUiState()
        state.applyAppearance(appearance(avatar: "https://cdn.example/chat360.png"), chatboxName: nil)
        state.applyAppearance(appearance(avatar: "https://cdn.example/other.png"), chatboxName: nil)
        XCTAssertEqual(state.logoOverride, other)
    }

    func testTheHyundaiLogoStillShowsAfterAServerLogoArrivesAndThenADrop() {
        var state = ChatUiState()
        state.applyAppearance(appearance(avatar: "https://cdn.example/chat360.png"), chatboxName: nil)
        state.applyAppearance(nil, chatboxName: nil)
        XCTAssertEqual(resolveLogo(configured: hyundai, fromServer: state.logoOverride), hyundai)
    }

    func testOtherAppearanceFieldsBehaveAsBefore() {
        var state = ChatUiState()
        state.applyAppearance(appearance(avatar: nil), chatboxName: "Hyundai Sales")
        XCTAssertEqual(state.botTitleOverride, "Hyundai Sales")
        state.applyAppearance(nil, chatboxName: " ")
        XCTAssertNil(state.botTitleOverride, "a blank name clears the title")
    }
}
