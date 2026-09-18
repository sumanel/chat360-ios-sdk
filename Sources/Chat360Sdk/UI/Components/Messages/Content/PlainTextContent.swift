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
        if #available(iOS 16.0, *), let split = HTMLTableExtractor.extractFirstTable(from: text) {
            VStack(alignment: .leading, spacing: 10) {
                // The surrounding markup is rendered as rich text, not stripped first, so bold,
                // italic and links in the paragraph around the table survive.
                textView(split.beforeHTML, trimEdges: true)
                HTMLTableView(headers: split.table.headers, rows: split.table.rows)
                textView(split.afterHTML, trimEdges: true)
            }
        } else {
            textView(text)
        }
    }

    /// One run of bot-authored HTML as styled text; renders nothing (and takes no spacing slot) if it
    /// holds no visible text - e.g. the `</p>` left over after the table.
    @ViewBuilder
    private func textView(_ html: String, trimEdges: Bool = false) -> some View {
        let converted = html.toAttributedString(linkColor: colors.accent)
        let attributed = trimEdges ? converted.trimmingEdgeNewlines() : converted
        if !attributed.characters.isEmpty {
            Text(attributed)
                .font(typography.textFamily.font(size: 15))
                .lineSpacing(7)
                .foregroundColor(colors.bubbleAiText)
        }
    }
}
