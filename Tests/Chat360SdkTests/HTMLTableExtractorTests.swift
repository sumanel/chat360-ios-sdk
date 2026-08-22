import XCTest
@testable import Chat360SDK

final class HTMLTableExtractorTests: XCTestCase {
    func testExtractsHeadersAndRowsFromRealBotResponse() {
        let html = """
        <table border="1" style="border-collapse:collapse">
        <tr><th>Parameter</th><th>Hyundai CRETA</th><th>Kia Seltos</th></tr>
        <tr><td>Price (Top Variant)</td><td>Rs 18,68,000 (King 1.5 Petrol IVT)</td><td>Rs 19,49,000 (GTX(A) IVT)</td></tr>
        <tr><td>Fuel Tank Capacity</td><td>50L</td><td>47L</td></tr>
        </table>
        """

        guard let result = HTMLTableExtractor.extractFirstTable(from: html) else {
            return XCTFail("Expected a table to be extracted")
        }

        XCTAssertEqual(result.table.headers, ["Parameter", "Hyundai CRETA", "Kia Seltos"])
        XCTAssertEqual(result.table.rows.count, 2)
        XCTAssertEqual(result.table.rows[0], ["Price (Top Variant)", "Rs 18,68,000 (King 1.5 Petrol IVT)", "Rs 19,49,000 (GTX(A) IVT)"])
        XCTAssertEqual(result.table.rows[1], ["Fuel Tank Capacity", "50L", "47L"])
        XCTAssertTrue(result.before.isEmpty)
        XCTAssertTrue(result.after.isEmpty)
    }

    func testPreservesSurroundingTextBeforeAndAfterTheTable() {
        let html = "<p>Here's a comparison:</p><table><tr><th>A</th></tr><tr><td>1</td></tr></table><p>Let me know if you want more.</p>"

        guard let result = HTMLTableExtractor.extractFirstTable(from: html) else {
            return XCTFail("Expected a table to be extracted")
        }

        XCTAssertEqual(result.before, "Here's a comparison:")
        XCTAssertEqual(result.after, "Let me know if you want more.")
        XCTAssertEqual(result.table.headers, ["A"])
        XCTAssertEqual(result.table.rows, [["1"]])
    }

    func testReturnsNilWhenThereIsNoTable() {
        XCTAssertNil(HTMLTableExtractor.extractFirstTable(from: "<p>Just a plain reply.</p>"))
    }

    func testStripsNestedTagsInsideCells() {
        let html = "<table><tr><th>Name</th></tr><tr><td><b>Bold</b> text</td></tr></table>"
        let result = HTMLTableExtractor.extractFirstTable(from: html)
        XCTAssertEqual(result?.table.rows, [["Bold text"]])
    }
}
