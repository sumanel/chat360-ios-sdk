import SwiftUI

// `Grid`/`GridRow` (not a plain VStack of independent per-row HStacks) is what actually keeps
// columns aligned across rows here - each row previously sized its own cells independently, so
// a row with a long label (e.g. "Fuel Tank Capacity") ended up wider than a row with a short one
// ("Segment"), and with nothing syncing widths across rows, every row drifted to a different
// column position - a staircase, not a table. Grid measures each column's width from the widest
// cell anywhere in that column, across every row, which is the actual fix.
@available(iOS 16.0, *)
struct HTMLTableView: View {
    @Environment(\.chat360Colors) private var colors
    @Environment(\.chat360Typography) private var typography

    let headers: [String]
    let rows: [[String]]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: true) {
            Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow {
                    ForEach(Array(headers.enumerated()), id: \.offset) { _, header in
                        cell(header, isHeader: true)
                    }
                }
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    GridRow {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, value in
                            cell(value, isHeader: false)
                        }
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
            .frame(minWidth: 90, alignment: .leading)
            .background(isHeader ? colors.backgroundSunken : colors.bubbleAiBackground)
            .overlay(Rectangle().stroke(colors.cardBorder, lineWidth: 0.5))
    }
}
