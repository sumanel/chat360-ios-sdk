import XCTest
@testable import Chat360SDK

final class IncomingEnvelopeTests: XCTestCase {
    func testUpdateStatusFlipsToLiveChatEndedRegardlessOfOtherFields() {
        let envelope = RawSocketEnvelope(user: "admin", update_status: true)
        guard case .liveChatEnded = envelope.toIncomingEvent() else {
            return XCTFail("expected liveChatEnded")
        }
    }

    func testAssignedUserPresentMapsToAgentAssignedWithRightFields() {
        let data: JSONValue = .object([
            "assigned_user": .object([
                "operator_name": .string("Jordan"),
                "user_designation": .string("Support Lead"),
                "avatar": .string("https://example.com/a.png"),
            ])
        ])
        let envelope = RawSocketEnvelope(user: "bot", data: data)
        guard case .agentAssigned(let agent) = envelope.toIncomingEvent() else {
            return XCTFail("expected agentAssigned")
        }
        XCTAssertEqual(agent.name, "Jordan")
        XCTAssertEqual(agent.designation, "Support Lead")
        XCTAssertEqual(agent.avatarUrl, "https://example.com/a.png")
    }

    func testAssignedUserTakesPrecedenceOverOtherwiseNormalBotNode() {
        let data: JSONValue = .object([
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
        let data: JSONValue = .object([
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
        let data: JSONValue = .object(["nodeType": .string("TEXT"), "questionText": .string("Hi, how can I help?")])
        let envelope = RawSocketEnvelope(user: "admin", data: data)
        guard case .botMessage(let node) = envelope.toIncomingEvent() else {
            return XCTFail("expected botMessage")
        }
        XCTAssertEqual(node.author, .agent)
    }

    func testOperatorAuthoredMessageAlsoDispatchesAsBotMessageTaggedAgent() {
        let data: JSONValue = .object(["nodeType": .string("TEXT"), "questionText": .string("Following up on your request")])
        let envelope = RawSocketEnvelope(user: "operator", data: data)
        guard case .botMessage(let node) = envelope.toIncomingEvent() else {
            return XCTFail("expected botMessage")
        }
        XCTAssertEqual(node.author, .agent)
    }

    func testBotAuthoredMessageStillDispatchesTaggedBot() {
        let data: JSONValue = .object(["nodeType": .string("TEXT"), "questionText": .string("Hello from the bot")])
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

    func testChatgptMessageChunkWithNestedDataKeepsItsHtmlTagsUnstripped() {
        let data: JSONValue = .object(["questionText": .string("- <stro")])
        let envelope = RawSocketEnvelope(user: "bot", type: "chatgpt_message", data: data, stream_id: "s1", end_stream: false)
        guard case .botMessage(let node) = envelope.toIncomingEvent() else {
            return XCTFail("expected botMessage")
        }
        XCTAssertEqual(node.streamId, "s1")
        XCTAssertEqual(node.streamEnded, false)
        XCTAssertEqual(node.text, "- <stro")
    }

    func testChatgptMessageChunkWithNoNestedDataKeepsItsHtmlTagsUnstripped() {
        let envelope = RawSocketEnvelope(user: "bot", type: "chatgpt_message", message: .string("ng>Design</strong>: modern"), stream_id: "s1", end_stream: true)
        guard case .botMessage(let node) = envelope.toIncomingEvent() else {
            return XCTFail("expected botMessage")
        }
        XCTAssertEqual(node.text, "ng>Design</strong>: modern")
    }

    func testMergingRawChunksSplitMidTagThenParsingOnceRecoversRealBoldFormatting() {
        let chunk1 = "Key features.\n- <stro"
        let chunk2 = "ng>Design</strong>: modern and sporty"
        let parsed = RichTextParser.parse(chunk1 + chunk2)
        let textRuns: [RichText.TextRun] = parsed.runs.compactMap {
            if case .textRun(let run) = $0 { return run }
            return nil
        }
        XCTAssertEqual(textRuns[0].text, "Key features.\n- ")
        XCTAssertFalse(textRuns[0].bold)
        XCTAssertEqual(textRuns[1].text, "Design")
        XCTAssertTrue(textRuns[1].bold)
        XCTAssertEqual(textRuns[2].text, ": modern and sporty")
        XCTAssertFalse(textRuns[2].bold)

        let parsedIndividuallyThenJoined = RichTextParser.parse(chunk1).runs + RichTextParser.parse(chunk2).runs
        let joinedText = parsedIndividuallyThenJoined.compactMap { run -> String? in
            if case .textRun(let textRun) = run { return textRun.text }
            return nil
        }.joined()
        XCTAssertTrue(joinedText.contains("<strong>"))
    }

    func testBotMessageTimeFieldParsesIntoNodeTimestampMsUtc() {
        let data: JSONValue = .object(["nodeType": .string("TEXT"), "questionText": .string("Hi")])
        let envelope = RawSocketEnvelope(user: "bot", data: data, time: "12/08/2026 20:04:53")
        guard case .botMessage(let node) = envelope.toIncomingEvent(), let timestampMs = node.timestampMs else {
            return XCTFail("expected botMessage with timestampMs")
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let date = Date(timeIntervalSince1970: Double(timestampMs) / 1000)
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 8)
        XCTAssertEqual(components.day, 12)
        XCTAssertEqual(components.hour, 20)
        XCTAssertEqual(components.minute, 4)
        XCTAssertEqual(components.second, 53)
    }

    func testEchoedUserMessageTimeFieldParsesIntoTimestampMs() {
        let envelope = RawSocketEnvelope(user: "end_user", message: .string("hi"), time: "12/08/2026 20:04:40")
        guard case .echoedUserMessage(_, _, let timestampMs) = envelope.toIncomingEvent() else {
            return XCTFail("expected echoedUserMessage")
        }
        XCTAssertNotNil(timestampMs)
    }

    func testMissingTimeFieldLeavesTimestampMsNilRatherThanThrowing() {
        let data: JSONValue = .object(["nodeType": .string("TEXT"), "questionText": .string("Hi")])
        let envelope = RawSocketEnvelope(user: "bot", data: data)
        guard case .botMessage(let node) = envelope.toIncomingEvent() else {
            return XCTFail("expected botMessage")
        }
        XCTAssertNil(node.timestampMs)
    }

    func testTimestampIntWinsOverTimeWhenBothPresent() {
        let data: JSONValue = .object(["nodeType": .string("TEXT"), "questionText": .string("Hi")])
        let envelope = RawSocketEnvelope(user: "bot", data: data, time: "01/01/2000 00:00:00", timestamp_int: "1786565354.987089")
        guard case .botMessage(let node) = envelope.toIncomingEvent() else {
            return XCTFail("expected botMessage")
        }
        XCTAssertEqual(node.timestampMs, 1786565354987)
    }

    func testUnparseableTimeFieldLeavesTimestampMsNilRatherThanThrowing() {
        let data: JSONValue = .object(["nodeType": .string("TEXT"), "questionText": .string("Hi")])
        let envelope = RawSocketEnvelope(user: "bot", data: data, time: "not-a-date")
        guard case .botMessage(let node) = envelope.toIncomingEvent() else {
            return XCTFail("expected botMessage")
        }
        XCTAssertNil(node.timestampMs)
    }
}
