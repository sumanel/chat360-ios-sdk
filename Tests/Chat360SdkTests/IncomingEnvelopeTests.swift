import XCTest
@testable import Chat360SDK

final class IncomingEnvelopeTests: XCTestCase {

    func testUpdateStatusFlipsToLiveChatEndedRegardlessOfOtherFields() {
        let envelope = RawSocketEnvelope(user: "admin", update_status: true)
        XCTAssertEqual(envelope.toIncomingEvent(), .liveChatEnded)
    }

    func testAssignedUserPresentMapsToAgentAssignedWithTheRightFields() {
        let data = JSONValue.object([
            "assigned_user": .object([
                "operator_name": .string("Jordan"),
                "user_designation": .string("Support Lead"),
                "avatar": .string("https://example.com/a.png"),
            ]),
        ])
        let envelope = RawSocketEnvelope(user: "bot", data: data)
        guard case .agentAssigned(let agent) = envelope.toIncomingEvent() else {
            return XCTFail("expected agentAssigned")
        }
        XCTAssertEqual(agent.name, "Jordan")
        XCTAssertEqual(agent.designation, "Support Lead")
        XCTAssertEqual(agent.avatarUrl, "https://example.com/a.png")
    }

    func testAssignedUserTakesPrecedenceOverAnOtherwiseNormalBotNode() {
        let data = JSONValue.object([
            "nodeType": .string("MULTI_CHOICE"),
            "questionText": .string("Pick one"),
            "assigned_user": .object(["operator_name": .string("Riley")]),
        ])
        let envelope = RawSocketEnvelope(user: "bot", data: data)
        guard case .agentAssigned = envelope.toIncomingEvent() else {
            return XCTFail("expected agentAssigned")
        }
    }

    func testEmptyAssignedUserObjectIsIgnoredFallsThroughToNormalBotDispatch() {
        let data = JSONValue.object([
            "nodeType": .string("TEXT"),
            "questionText": .string("Hello"),
            "assigned_user": .object([:]),
        ])
        let envelope = RawSocketEnvelope(user: "bot", data: data)
        guard case .botMessage = envelope.toIncomingEvent() else {
            return XCTFail("expected botMessage")
        }
    }

    func testAdminAuthoredMessageDispatchesAsBotMessageTaggedAgent() {
        let data = JSONValue.object([
            "nodeType": .string("TEXT"),
            "questionText": .string("Hi, how can I help?"),
        ])
        let envelope = RawSocketEnvelope(user: "admin", data: data)
        guard case .botMessage(let node) = envelope.toIncomingEvent() else {
            return XCTFail("expected botMessage")
        }
        XCTAssertEqual(node.author, .agent)
    }

    func testOperatorAuthoredMessageAlsoDispatchesAsBotMessageTaggedAgent() {
        let data = JSONValue.object([
            "nodeType": .string("TEXT"),
            "questionText": .string("Following up on your request"),
        ])
        let envelope = RawSocketEnvelope(user: "operator", data: data)
        guard case .botMessage(let node) = envelope.toIncomingEvent() else {
            return XCTFail("expected botMessage")
        }
        XCTAssertEqual(node.author, .agent)
    }

    func testBotAuthoredMessageStillDispatchesTaggedBotNoRegression() {
        let data = JSONValue.object([
            "nodeType": .string("TEXT"),
            "questionText": .string("Hello from the bot"),
        ])
        let envelope = RawSocketEnvelope(user: "bot", data: data)
        guard case .botMessage(let node) = envelope.toIncomingEvent() else {
            return XCTFail("expected botMessage")
        }
        XCTAssertEqual(node.author, .bot)
    }

    func testUnrecognizedUserWithNoDataFallsThroughToUnhandled() {
        let envelope = RawSocketEnvelope(user: "someone_else", data: nil)
        guard case .unhandled = envelope.toIncomingEvent() else {
            return XCTFail("expected unhandled")
        }
    }

    // MARK: - chatgpt_message streaming: text must stay raw/unstripped per chunk

    func testChatgptMessageChunkWithNestedDataKeepsItsHtmlTagsUnstripped() {
        let data = JSONValue.object(["questionText": .string("- <stro")])
        let envelope = RawSocketEnvelope(user: "bot", type: "chatgpt_message", data: data, stream_id: "s1", end_stream: false)
        guard case .botMessage(let node) = envelope.toIncomingEvent() else {
            return XCTFail("expected botMessage")
        }
        XCTAssertEqual(node.streamId, "s1")
        XCTAssertEqual(node.streamEnded, false)
        // Not "- <stro" with the dangling tag start stripped away - a lone chunk must never run
        // strippingHtml(), since the matching ">" may only arrive in the next chunk.
        XCTAssertEqual(node.text, "- <stro")
    }

    func testChatgptMessageChunkWithNoNestedDataKeepsItsHtmlTagsUnstripped() {
        let envelope = RawSocketEnvelope(
            user: "bot",
            type: "chatgpt_message",
            message: .string("ng>Design</strong>: modern"),
            stream_id: "s1",
            end_stream: true
        )
        guard case .botMessage(let node) = envelope.toIncomingEvent() else {
            return XCTFail("expected botMessage")
        }
        XCTAssertEqual(node.text, "ng>Design</strong>: modern")
    }

    func testMergingRawChunksSplitMidTagThenParsingOnceRecoversRealBoldFormatting() {
        // Reproduces the real-world split: chunk N ends mid open-tag, chunk N+1 finishes it.
        let chunk1 = "Key features.\n- <stro"
        let chunk2 = "ng>Design</strong>: modern and sporty"
        let parsed = RichTextParser.parse(chunk1 + chunk2)
        let textRuns = parsed.textRuns
        XCTAssertEqual(textRuns[0].text, "Key features.\n- ")
        XCTAssertFalse(textRuns[0].bold)
        XCTAssertEqual(textRuns[1].text, "Design")
        XCTAssertTrue(textRuns[1].bold)
        XCTAssertEqual(textRuns[2].text, ": modern and sporty")
        XCTAssertFalse(textRuns[2].bold)
        // Parsing each chunk individually before concatenating is exactly the bug this reproduces:
        // the dangling "<stro" / "ng>" halves never form a complete tag on their own, so a naive
        // per-chunk parse would leave "<strong>" as literal text instead of real bold.
        let parsedIndividuallyThenJoined = RichTextParser.parse(chunk1).runs + RichTextParser.parse(chunk2).runs
        let joinedText = parsedIndividuallyThenJoined.compactMap {
            if case .text(let run) = $0 { return run.text }
            return nil
        }.joined()
        XCTAssertTrue(joinedText.contains("<strong>"))
    }
}
