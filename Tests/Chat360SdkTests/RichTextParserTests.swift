import XCTest
@testable import Chat360SDK

final class RichTextParserTests: XCTestCase {
    private func textRuns(_ richText: RichText) -> [RichText.TextRun] {
        richText.runs.compactMap { run -> RichText.TextRun? in
            if case .textRun(let textRun) = run { return textRun }
            return nil
        }
    }

    func testPlainTextWithNoTagsPassesThroughAsSingleUnstyledRun() {
        let parsed = RichTextParser.parse("Hello there")
        XCTAssertEqual(parsed.runs, [.textRun(RichText.TextRun(text: "Hello there"))])
    }

    func testBoldAndStrongBothProduceABoldRun() {
        XCTAssertTrue(textRuns(RichTextParser.parse("<b>x</b>")).first!.bold)
        XCTAssertTrue(textRuns(RichTextParser.parse("<strong>x</strong>")).first!.bold)
    }

    func testItalicUnderlineAndStrikethroughTagsSetTheirFlags() {
        XCTAssertTrue(textRuns(RichTextParser.parse("<em>x</em>")).first!.italic)
        XCTAssertTrue(textRuns(RichTextParser.parse("<u>x</u>")).first!.underline)
        XCTAssertTrue(textRuns(RichTextParser.parse("<del>x</del>")).first!.strikethrough)
    }

    func testNestedTagsCombineTheirStyles() {
        let run = textRuns(RichTextParser.parse("<strong><em>bold italic</em></strong>")).first!
        XCTAssertTrue(run.bold)
        XCTAssertTrue(run.italic)
        XCTAssertEqual(run.text, "bold italic")
    }

    func testOutOfOrderClosingTagsStillCloseBoth() {
        let runs = textRuns(RichTextParser.parse("<b><i>x</i></b>y"))
        XCTAssertEqual(runs[0].text, "x")
        XCTAssertTrue(runs[0].bold)
        XCTAssertTrue(runs[0].italic)
        XCTAssertEqual(runs[1].text, "y")
        XCTAssertFalse(runs[1].bold)
        XCTAssertFalse(runs[1].italic)
    }

    func testUnmatchedClosingTagIsIgnoredRatherThanThrowing() {
        let parsed = RichTextParser.parse("hello</b>world")
        XCTAssertEqual(textRuns(parsed).map { $0.text }.joined(), "helloworld")
    }

    func testBrProducesALineBreak() {
        let parsed = RichTextParser.parse("line1<br>line2")
        XCTAssertEqual(parsed.runs, [.textRun(RichText.TextRun(text: "line1")), .lineBreak, .textRun(RichText.TextRun(text: "line2"))])
    }

    func testParagraphsBecomeLineBreaksBetweenThem() {
        let parsed = RichTextParser.parse("<p>one</p><p>two</p>")
        XCTAssertEqual(textRuns(parsed).map { $0.text }, ["one", "two"])
        XCTAssertTrue(parsed.runs.contains { if case .lineBreak = $0 { return true } else { return false } })
    }

    func testUnorderedListItemsGetBulletMarkers() {
        let parsed = RichTextParser.parse("<ul><li>first</li><li>second</li></ul>")
        XCTAssertEqual(textRuns(parsed).map { $0.text }, ["\u{2022} ", "first", "\u{2022} ", "second"])
    }

    func testOrderedListItemsGetIncrementingNumericMarkers() {
        let parsed = RichTextParser.parse("<ol><li>first</li><li>second</li></ol>")
        XCTAssertEqual(textRuns(parsed).map { $0.text }, ["1. ", "first", "2. ", "second"])
    }

    func testAnchorTagCapturesHrefAsALinkRun() {
        let run = textRuns(RichTextParser.parse("<a href=\"https://example.com\">click me</a>")).first!
        XCTAssertEqual(run.text, "click me")
        XCTAssertEqual(run.linkUrl, "https://example.com")
    }

    func testCommonHtmlEntitiesAreDecoded() {
        let text = textRuns(RichTextParser.parse("Tom &amp; Jerry &lt;3 &quot;fun&quot;")).first!.text
        XCTAssertEqual(text, "Tom & Jerry <3 \"fun\"")
    }

    func testNumericEntitiesAreDecoded() {
        XCTAssertEqual(textRuns(RichTextParser.parse("&#65;")).first!.text, "A")
        XCTAssertEqual(textRuns(RichTextParser.parse("&#x41;")).first!.text, "A")
    }

    func testIncompleteTrailingTagIsKeptAsLiteralTextInsteadOfThrowing() {
        let parsed = RichTextParser.parse("Key features.\n- <stro")
        XCTAssertEqual(textRuns(parsed).first!.text, "Key features.\n- <stro")
    }

    func testTagSplitAcrossTwoChunksResolvesCorrectlyOnceMergedStringIsParsed() {
        let merged = "Key features.\n- <stro" + "ng>Design</strong>: modern and sporty"
        let runs = textRuns(RichTextParser.parse(merged))
        XCTAssertEqual(runs[0].text, "Key features.\n- ")
        XCTAssertFalse(runs[0].bold)
        XCTAssertEqual(runs[1].text, "Design")
        XCTAssertTrue(runs[1].bold)
        XCTAssertEqual(runs[2].text, ": modern and sporty")
        XCTAssertFalse(runs[2].bold)
    }

    func testUnknownTagsAreDroppedButTheirInnerTextIsKept() {
        let parsed = RichTextParser.parse("<weirdtag>hello</weirdtag>")
        XCTAssertEqual(textRuns(parsed).map { $0.text }.joined(), "hello")
    }
}
