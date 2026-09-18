import XCTest
@testable import Chat360SDK

/// Regression tests for "the paragraph after the table doesn't render". A knowledge-base reply is a
/// `<table>` followed by a summary `<p>`, often wrapped in a `<p>` by the flow, and it arrives as a
/// multiple-choice node (the reply plus "Venue vs Nexon" style quick replies) with literal `\n`
/// escapes for newlines. The message below is the real one that was reported.
final class TableWithTrailingParagraphTests: XCTestCase {

    private let summary = "The Hyundai Venue stands out with its diesel engine option delivering high torque and advanced drive modes including Sand, Mud, and Snow traction control, making it a strong, well-rounded choice in this segment."

    /// The reply as reported: newlines between tags, indented cells, trailing summary paragraph.
    private var venueVsBrezza: String {
        """
        <table border="1" style="border-collapse:collapse; width:100%;">
        <thead>
        <tr>
            <th>Parameter</th>
            <th>Hyundai Venue</th>
            <th>Maruti Suzuki Brezza</th>
        </tr>
        </thead>
        <tbody>
        <tr>
            <td><strong>Fuel Type Options</strong></td>
            <td>Petrol and Diesel</td>
            <td>Petrol and CNG (bi-fuel)</td>
        </tr>
        <tr>
            <td><strong>Maximum Power</strong></td>
            <td>116 PS (Diesel), 120 PS (Petrol Turbo GDi)</td>
            <td>110 PS (Petrol)</td>
        </tr>
        <tr>
            <td><strong>Maximum Torque</strong></td>
            <td>250 Nm (Diesel), Not specified for Petrol</td>
            <td>130 Nm (Petrol)</td>
        </tr>
        <tr>
            <td><strong>Transmission Options</strong></td>
            <td>7-speed DCT (Petrol Turbo), Manual and Automatic options</td>
            <td>Manual and Automatic options</td>
        </tr>
        <tr>
            <td><strong>Drive Modes and Traction Control</strong></td>
            <td>Drive Mode Select and Sand, Mud, and Snow traction modes</td>
            <td>Not available</td>
        </tr>
        </tbody>
        </table>
        <p>\(summary)</p>
        """
    }

    private func assertVenueTableAndSummary(_ text: String, file: StaticString = #filePath, line: UInt = #line) {
        guard let result = HTMLTableExtractor.extractFirstTable(from: text) else {
            return XCTFail("the message was not recognised as a table", file: file, line: line)
        }
        XCTAssertEqual(result.table.headers, ["Parameter", "Hyundai Venue", "Maruti Suzuki Brezza"], file: file, line: line)
        XCTAssertEqual(result.table.rows.count, 5, file: file, line: line)
        XCTAssertEqual(result.table.rows[0], ["Fuel Type Options", "Petrol and Diesel", "Petrol and CNG (bi-fuel)"], file: file, line: line)
        XCTAssertEqual(result.after, summary, "the paragraph after the table was lost", file: file, line: line)
        XCTAssertEqual(result.before, "", file: file, line: line)
    }

    func testTheParagraphAfterTheTableIsKept() {
        assertVenueTableAndSummary(venueVsBrezza)
    }

    func testTheFlowsWrappingPTagAroundTheWholeReplyDoesNotLoseTheParagraph() {
        assertVenueTableAndSummary("<p>" + venueVsBrezza + "</p>")
    }

    func testLiteralBackslashNEscapesAndThreeQuickRepliesSurviveTheWireParserAndStillYieldTheParagraph() {
        // Exactly what the socket delivers: newlines arrive as the two characters backslash + n.
        let onTheWire = venueVsBrezza.replacingOccurrences(of: "\n", with: "\\n")
        let data: JSONValue = .object([
            "nodeType": .string("MULTI_CHOICE"),
            "questionText": .string(onTheWire),
            "buttons": .array(["Venue vs Nexon", "Venue vs Sonet", "Venue vs Creta"].enumerated().map { index, label in
                .object(["text": .string(label), "targetId": .string("t\(index)")])
            }),
        ])

        let event = RawSocketEnvelope(user: "bot", data: data).toIncomingEvent()

        guard case .botMessage(let node) = event else { return XCTFail("expected a bot message, got \(event)") }
        assertVenueTableAndSummary(node.text ?? "")
        guard case .multiChoice(let choice) = node.content else { return XCTFail("expected multi-choice content") }
        XCTAssertEqual(choice.options.map { $0.text }, ["Venue vs Nexon", "Venue vs Sonet", "Venue vs Creta"])
    }

    func testTextBeforeAndAfterTheTableIsKept() {
        let html = "<p>Here is the comparison:</p><table><tr><th>A</th></tr><tr><td>1</td></tr></table><p>See the spec for more.</p>"

        let result = HTMLTableExtractor.extractFirstTable(from: html)

        XCTAssertEqual(result?.before, "Here is the comparison:")
        XCTAssertEqual(result?.after, "See the spec for more.")
    }

    func testATableWithNothingAfterItLeavesNoTrailingText() {
        let result = HTMLTableExtractor.extractFirstTable(from: "<table><tr><th>A</th></tr><tr><td>1</td></tr></table>")
        XCTAssertEqual(result?.after, "")
        XCTAssertEqual(result?.before, "")
    }

    func testOnlyTheFirstTableIsStructuredAndTheRestStaysAsTextAfterIt() {
        let result = HTMLTableExtractor.extractFirstTable(
            from: "<table><tr><th>H</th></tr><tr><td>one</td></tr></table><p>middle</p><table><tr><td>two</td></tr></table>"
        )
        XCTAssertEqual(result?.table.rows.count, 1)
        XCTAssertTrue(result?.after.contains("middle") == true)
    }

    func testUpperCaseTagsAreRecognisedToo() {
        let result = HTMLTableExtractor.extractFirstTable(from: "<TABLE><TR><TH>A</TH></TR><TR><TD>1</TD></TR></TABLE><P>after</P>")
        XCTAssertNotNil(result, "an upper-case table was not recognised")
        XCTAssertEqual(result?.after, "after")
    }

    // MARK: - Formatting around the table

    private let formatted = #"<p>Here is <b>the</b> comparison:</p><table><tr><th>A</th></tr><tr><td>1</td></tr></table><p>See <a href="https://example.com/spec">the spec</a> for <em>more</em>.</p>"#

    /// The trailing paragraph used to be reduced to bare words before it was rendered, so bold,
    /// italic and links in it disappeared.
    func testFormattingAndLinksInTheTextAroundTheTableSurviveIntoTheRenderedString() throws {
        let split = try XCTUnwrap(HTMLTableExtractor.extractFirstTable(from: formatted))

        let before = RichTextParser.parse(split.beforeHTML)
        let after = RichTextParser.parse(split.afterHTML)
        let beforeRuns = before.runs.compactMap { run -> RichText.TextRun? in if case .textRun(let r) = run { return r } else { return nil } }
        let afterRuns = after.runs.compactMap { run -> RichText.TextRun? in if case .textRun(let r) = run { return r } else { return nil } }
        XCTAssertTrue(beforeRuns.contains { $0.bold && $0.text == "the" }, "bold before the table was lost")
        XCTAssertTrue(afterRuns.contains { $0.linkUrl == "https://example.com/spec" }, "the link after the table was lost")
        XCTAssertTrue(afterRuns.contains { $0.italic && $0.text == "more" }, "italic after the table was lost")
    }

    /// The exact conversion `PlainTextContent` applies to each segment.
    @available(iOS 15.0, *)
    func testTheStringActuallyRenderedForTheTrailingParagraphStillCarriesItsLink() throws {
        let split = try XCTUnwrap(HTMLTableExtractor.extractFirstTable(from: formatted))

        let rendered = split.afterHTML.toAttributedString(linkColor: .blue).trimmingEdgeNewlines()

        XCTAssertEqual(String(rendered.characters), "See the spec for more.", "the closing </p> left a blank line under the paragraph")
        XCTAssertTrue(rendered.runs.contains { $0.link == URL(string: "https://example.com/spec") }, "no link in the rendered trailing paragraph")
    }

    func testTheWrappingTagsAroundTheReplyLeaveNothingVisibleBeforeTheTable() throws {
        let split = try XCTUnwrap(HTMLTableExtractor.extractFirstTable(from: "<p>" + venueVsBrezza + "</p>"))

        XCTAssertTrue(RichTextParser.parse(split.beforeHTML).runs.isEmpty, "a stray wrapper tag would render as an empty text block")
        XCTAssertEqual(split.before, "")
        XCTAssertEqual(split.after, summary)
    }

    func testTheStrippedBeforeAndAfterStayAvailableForPlainTextCallers() throws {
        let split = try XCTUnwrap(HTMLTableExtractor.extractFirstTable(from: formatted))

        XCTAssertEqual(split.before, "Here is the comparison:")
        XCTAssertEqual(split.after, "See the spec for more.")
    }

    @available(iOS 15.0, *)
    func testEdgeNewlineTrimmingOnlyTouchesTheEndsAndKeepsInnerBreaksAndStyling() {
        var attributed = AttributedString("\n\nfirst\nsecond\n")
        attributed.link = URL(string: "https://example.com")

        let trimmed = attributed.trimmingEdgeNewlines()

        XCTAssertEqual(String(trimmed.characters), "first\nsecond")
        XCTAssertTrue(trimmed.runs.allSatisfy { $0.link != nil }, "trimming dropped the styling")
        XCTAssertEqual(String(AttributedString("").trimmingEdgeNewlines().characters), "")
    }
}
