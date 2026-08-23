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
    // Captures the cell's own opening-tag attributes (for rowspan/colspan) separately from its
    // inner content.
    private static let cellRegex = try! NSRegularExpression(pattern: "<t[hd]\\b([^>]*)>([\\s\\S]*?)</t[hd]>", options: [.caseInsensitive])
    private static let rowspanAttr = try! NSRegularExpression(pattern: "rowspan\\s*=\\s*\"?(\\d+)\"?", options: [.caseInsensitive])
    private static let colspanAttr = try! NSRegularExpression(pattern: "colspan\\s*=\\s*\"?(\\d+)\"?", options: [.caseInsensitive])

    private struct RawCell {
        let text: String
        let rowspan: Int
        let colspan: Int
    }

    // A cell still "spilling" into a later row from an earlier rowspan, parked at the column it
    // occupies until its remaining count runs out.
    private struct PendingSpan {
        var remaining: Int
        let value: String
    }

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

        let rawRows = parseRawRows(from: innerHTML)
        let grid = resolveSpans(rawRows)
        guard let headerRow = grid.first else { return nil }
        return (before, ParsedHTMLTable(headers: headerRow, rows: Array(grid.dropFirst())), after)
    }

    private static func parseRawRows(from innerHTML: String) -> [[RawCell]] {
        let innerNSString = innerHTML as NSString
        let rowMatches = rowRegex.matches(in: innerHTML, range: NSRange(location: 0, length: innerNSString.length))
        return rowMatches.map { rowMatch in
            let rowInner = innerNSString.substring(with: rowMatch.range(at: 1))
            let rowNSString = rowInner as NSString
            let cellMatches = cellRegex.matches(in: rowInner, range: NSRange(location: 0, length: rowNSString.length))
            return cellMatches.map { cellMatch -> RawCell in
                let attrs = rowNSString.substring(with: cellMatch.range(at: 1))
                let text = rowNSString.substring(with: cellMatch.range(at: 2)).strippedHtml()
                let rowspan = firstIntGroup(rowspanAttr, in: attrs) ?? 1
                let colspan = firstIntGroup(colspanAttr, in: attrs) ?? 1
                return RawCell(text: text, rowspan: max(1, rowspan), colspan: max(1, colspan))
            }
        }
    }

    // Walks the rows top to bottom, filling in any column still "owed" a value from an earlier
    // row's rowspan before consuming this row's own next cell - so a category label that only
    // appears once in the source HTML (merged down across several rows) still shows up in every
    // row it actually covers instead of every row after it silently losing a column.
    private static func resolveSpans(_ rawRows: [[RawCell]]) -> [[String]] {
        var pendingByColumn: [Int: PendingSpan] = [:]
        var grid: [[String]] = []

        for rawRow in rawRows {
            var resolvedRow: [String] = []
            var col = 0
            var cellIndex = 0

            while cellIndex < rawRow.count || pendingByColumn[col] != nil {
                if var pending = pendingByColumn[col], pending.remaining > 0 {
                    resolvedRow.append(pending.value)
                    pending.remaining -= 1
                    pendingByColumn[col] = pending.remaining > 0 ? pending : nil
                    col += 1
                    continue
                }
                guard cellIndex < rawRow.count else { break }
                let cell = rawRow[cellIndex]
                cellIndex += 1
                for span in 0..<cell.colspan {
                    resolvedRow.append(cell.text)
                    if cell.rowspan > 1 {
                        pendingByColumn[col + span] = PendingSpan(remaining: cell.rowspan - 1, value: cell.text)
                    }
                }
                col += cell.colspan
            }
            if !resolvedRow.isEmpty { grid.append(resolvedRow) }
        }
        return grid
    }

    private static func firstIntGroup(_ regex: NSRegularExpression, in text: String) -> Int? {
        let nsText = text as NSString
        guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: nsText.length)), match.numberOfRanges > 1 else {
            return nil
        }
        let range = match.range(at: 1)
        guard range.location != NSNotFound else { return nil }
        return Int(nsText.substring(with: range))
    }
}
