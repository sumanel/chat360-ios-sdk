import XCTest
@testable import Chat360SDK

final class RichTextParserTests: XCTestCase {

    private func texts(_ richText: RichText) -> [RichText.TextRun] {
        richText.textRuns
    }

    func testPlainTextWithNoTagsPassesThroughAsASingleUnstyledRun() {
        let parsed = RichTextParser.parse("Hello there")
        XCTAssertEqual(parsed.runs, [.text(RichText.TextRun(text: "Hello there"))])
    }

    func testBoldAndStrongBothProduceABoldRun() {
        XCTAssertEqual(texts(RichTextParser.parse("<b>x</b>")).first?.bold, true)
        XCTAssertEqual(texts(RichTextParser.parse("<strong>x</strong>")).first?.bold, true)
    }

    func testItalicUnderlineAndStrikethroughTagsSetTheirFlags() {
        XCTAssertEqual(texts(RichTextParser.parse("<em>x</em>")).first?.italic, true)
        XCTAssertEqual(texts(RichTextParser.parse("<u>x</u>")).first?.underline, true)
        XCTAssertEqual(texts(RichTextParser.parse("<del>x</del>")).first?.strikethrough, true)
    }

    func testNestedTagsCombineTheirStyles() {
        let run = texts(RichTextParser.parse("<strong><em>bold italic</em></strong>")).first!
        XCTAssertTrue(run.bold)
        XCTAssertTrue(run.italic)
        XCTAssertEqual(run.text, "bold italic")
    }

    func testOutOfOrderClosingTagsStillCloseBothMatchingLenientHtmlParsing() {
        // <b><i>x</b></i> - browsers close both b and i at the </b>.
        let runs = texts(RichTextParser.parse("<b><i>x</i></b>y"))
        XCTAssertEqual(runs[0].text, "x")
        XCTAssertTrue(runs[0].bold)
        XCTAssertTrue(runs[0].italic)
        XCTAssertEqual(runs[1].text, "y")
        XCTAssertFalse(runs[1].bold)
        XCTAssertFalse(runs[1].italic)
    }

    func testUnmatchedClosingTagIsIgnoredRatherThanThrowing() {
        let parsed = RichTextParser.parse("hello</b>world")
        XCTAssertEqual(texts(parsed).map(\.text).joined(), "helloworld")
    }

    func testBrProducesALineBreak() {
        let parsed = RichTextParser.parse("line1<br>line2")
        XCTAssertEqual(parsed.runs, [
            .text(RichText.TextRun(text: "line1")),
            .lineBreak,
            .text(RichText.TextRun(text: "line2")),
        ])
    }

    func testParagraphsBecomeLineBreaksBetweenThem() {
        let parsed = RichTextParser.parse("<p>one</p><p>two</p>")
        XCTAssertEqual(texts(parsed).map(\.text), ["one", "two"])
        XCTAssertTrue(parsed.runs.contains(.lineBreak))
    }

    func testUnorderedListItemsGetBulletMarkers() {
        let parsed = RichTextParser.parse("<ul><li>first</li><li>second</li></ul>")
        XCTAssertEqual(texts(parsed).map(\.text), ["\u{2022} ", "first", "\u{2022} ", "second"])
    }

    func testOrderedListItemsGetIncrementingNumericMarkers() {
        let parsed = RichTextParser.parse("<ol><li>first</li><li>second</li></ol>")
        XCTAssertEqual(texts(parsed).map(\.text), ["1. ", "first", "2. ", "second"])
    }

    func testAnchorTagCapturesHrefAsALinkRun() {
        let run = texts(RichTextParser.parse(#"<a href="https://example.com">click me</a>"#)).first!
        XCTAssertEqual(run.text, "click me")
        XCTAssertEqual(run.linkUrl, "https://example.com")
    }

    func testCommonHtmlEntitiesAreDecoded() {
        let text = texts(RichTextParser.parse("Tom &amp; Jerry &lt;3 &quot;fun&quot;")).first!.text
        XCTAssertEqual(text, "Tom & Jerry <3 \"fun\"")
    }

    func testNumericEntitiesAreDecoded() {
        XCTAssertEqual(texts(RichTextParser.parse("&#65;")).first?.text, "A")
        XCTAssertEqual(texts(RichTextParser.parse("&#x41;")).first?.text, "A")
    }

    func testAnIncompleteTrailingTagIsKeptAsLiteralTextInsteadOfThrowing() {
        // Exactly the streaming case: a chunk boundary lands mid-tag before the closing '>' arrives.
        let parsed = RichTextParser.parse("Key features.\n- <stro")
        XCTAssertEqual(texts(parsed).first?.text, "Key features.\n- <stro")
    }

    func testATagSplitAcrossTwoChunksResolvesCorrectlyOnceTheMergedStringIsParsed() {
        let merged = "Key features.\n- <stro" + "ng>Design</strong>: modern and sporty"
        let runs = texts(RichTextParser.parse(merged))
        XCTAssertEqual(runs[0].text, "Key features.\n- ")
        XCTAssertFalse(runs[0].bold)
        XCTAssertEqual(runs[1].text, "Design")
        XCTAssertTrue(runs[1].bold)
        XCTAssertEqual(runs[2].text, ": modern and sporty")
        XCTAssertFalse(runs[2].bold)
    }

    func testUnknownTagsAreDroppedButTheirInnerTextIsKept() {
        let parsed = RichTextParser.parse("<weirdtag>hello</weirdtag>")
        XCTAssertEqual(texts(parsed).map(\.text).joined(), "hello")
    }
}
