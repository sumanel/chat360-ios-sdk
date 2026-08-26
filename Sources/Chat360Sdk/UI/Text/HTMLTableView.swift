import SwiftUI

// A hand-rolled table layout instead of SwiftUI's `Grid` - Grid's own two-pass sizing didn't
// reconcile correctly with this view sitting inside a horizontal ScrollView: it settled on each
// row's height from an earlier pass (before the column width was actually constrained to
// `columnWidth`), so once the text wrapped at the real column width the row was already too
// short, and the extra lines spilled down over the row below instead of the row growing to fit
// them. Measuring and placing every cell manually here sidesteps that entirely - each row's
// height is computed directly from how tall its cells actually are once wrapped at the real
// column width, so a row can take however many lines its content needs, with no cap on row count
// or height.
@available(iOS 16.0, *)
struct HTMLTableView: View {
    @Environment(\.chat360Colors) private var colors
    @Environment(\.chat360Typography) private var typography

    let headers: [String]
    let rows: [[String]]

    private var columnCount: Int {
        max(headers.count, rows.map { $0.count }.max() ?? 0)
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: true) {
            HTMLTableLayout(columnCount: columnCount) {
                ForEach(Array(headers.enumerated()), id: \.offset) { _, header in
                    cell(header, isHeader: true)
                }
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    ForEach(Array(row.enumerated()), id: \.offset) { _, value in
                        cell(value, isHeader: false)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(colors.cardBorder, lineWidth: 1))
        }
    }

    private func cell(_ text: String, isHeader: Bool) -> some View {
        Text(text)
            .font(typography.textFamily.font(size: 13, weight: isHeader ? .semibold : .regular))
            .foregroundColor(colors.bubbleAiText)
            .multilineTextAlignment(.leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isHeader ? colors.backgroundSunken : colors.bubbleAiBackground)
            .overlay(Rectangle().stroke(colors.cardBorder, lineWidth: 0.5))
    }
}

// Lays out a flat list of cells (header row first, then each data row, left to right, top to
// bottom - exactly the order `HTMLTableView` declares them in) into a fixed number of equal-width
// columns, with each row's height taken directly from its tallest cell once wrapped at that
// column width.
@available(iOS 16.0, *)
private struct HTMLTableLayout: Layout {
    let columnCount: Int
    var columnWidth: CGFloat = 160

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard columnCount > 0 else { return .zero }
        var totalHeight: CGFloat = 0
        for rowSubviews in rows(of: subviews) {
            totalHeight += rowHeight(of: rowSubviews)
        }
        return CGSize(width: columnWidth * CGFloat(columnCount), height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard columnCount > 0 else { return }
        var y = bounds.minY
        for rowSubviews in rows(of: subviews) {
            let height = rowHeight(of: rowSubviews)
            var x = bounds.minX
            for subview in rowSubviews {
                subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(width: columnWidth, height: height))
                x += columnWidth
            }
            y += height
        }
    }

    private func rows(of subviews: Subviews) -> [[LayoutSubviews.Element]] {
        stride(from: 0, to: subviews.count, by: columnCount).map { start in
            Array(subviews[start..<min(start + columnCount, subviews.count)])
        }
    }

    private func rowHeight(of rowSubviews: [LayoutSubviews.Element]) -> CGFloat {
        rowSubviews.reduce(CGFloat(0)) { tallest, subview in
            max(tallest, subview.sizeThatFits(ProposedViewSize(width: columnWidth, height: nil)).height)
        }
    }
}
