import SwiftUI

@available(iOS 15.0, *)
public struct PlainTextContent: View {
    @Environment(\.chat360Colors) private var colors
    @Environment(\.chat360Typography) private var typography
    private let text: String

    public init(_ text: String) {
        self.text = text
    }

    public var body: some View {
        // HTMLTableView needs Grid (iOS 16+) to keep columns aligned across rows, so table
        // rendering is gated here rather than raising this whole type's own availability - this
        // type is reused by several other iOS 15-annotated content views that have nothing to do
        // with tables, and none of them need to be pulled up to 16 just for this one case.
        if #available(iOS 16.0, *), let (before, table, after) = HTMLTableExtractor.extractFirstTable(from: text) {
            VStack(alignment: .leading, spacing: 10) {
                textView(before)
                HTMLTableView(headers: table.headers, rows: table.rows)
                textView(after)
            }
        } else if !text.isEmpty {
            textView(text)
        }
    }

    @ViewBuilder
    private func textView(_ value: String) -> some View {
        if !value.isEmpty {
            Text(value.toAttributedString(linkColor: colors.accent))
                .font(typography.textFamily.font(size: 15))
                .lineSpacing(7)
                .foregroundColor(colors.bubbleAiText)
        }
    }
}
