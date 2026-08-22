import Foundation

struct ParsedHTMLTable: Equatable {
    let headers: [String]
    let rows: [[String]]
}

// `RichTextParser` treats any tag it doesn't recognize (including <table>/<tr>/<td>) as an
// invisible wrapper - it still emits the cell text, just with no row/column separation at all,
// which is why a bot response containing a table currently renders as one jumbled run-on
// sentence. This is a separate, narrow extractor specifically for the one case that needs
// actual structure rather than inline styling.
enum HTMLTableExtractor {
    private static let tableRegex = try! NSRegularExpression(pattern: "<table\\b[^>]*>([\\s\\S]*?)</table>", options: [.caseInsensitive])
    private static let rowRegex = try! NSRegularExpression(pattern: "<tr\\b[^>]*>([\\s\\S]*?)</tr>", options: [.caseInsensitive])
    private static let cellRegex = try! NSRegularExpression(pattern: "<t[hd]\\b[^>]*>([\\s\\S]*?)</t[hd]>", options: [.caseInsensitive])

    // Only the first <table> in the text is handled - a bot response with more than one is an
    // edge case not seen in practice, and everything after the first table's closing tag is
    // still shown, just as plain trailing text.
    static func extractFirstTable(from text: String) -> (before: String, table: ParsedHTMLTable, after: String)? {
        let nsText = text as NSString
        guard let match = tableRegex.firstMatch(in: text, range: NSRange(location: 0, length: nsText.length)) else { return nil }
        let fullRange = match.range(at: 0)
        let innerHTML = nsText.substring(with: match.range(at: 1))
        let before = nsText.substring(to: fullRange.location).strippedHtml()
        let after = nsText.substring(from: fullRange.location + fullRange.length).strippedHtml()

        let innerNSString = innerHTML as NSString
        let rowMatches = rowRegex.matches(in: innerHTML, range: NSRange(location: 0, length: innerNSString.length))
        var allRows: [[String]] = []
        for rowMatch in rowMatches {
            let rowInner = innerNSString.substring(with: rowMatch.range(at: 1))
            let rowNSString = rowInner as NSString
            let cellMatches = cellRegex.matches(in: rowInner, range: NSRange(location: 0, length: rowNSString.length))
            let cells = cellMatches.map { rowNSString.substring(with: $0.range(at: 1)).strippedHtml() }
            if !cells.isEmpty { allRows.append(cells) }
        }
        guard let headerRow = allRows.first else { return nil }
        return (before, ParsedHTMLTable(headers: headerRow, rows: Array(allRows.dropFirst())), after)
    }
}
