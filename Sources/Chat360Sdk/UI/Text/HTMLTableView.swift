import SwiftUI

@available(iOS 15.0, *)
struct HTMLTableView: View {
    @Environment(\.chat360Colors) private var colors
    @Environment(\.chat360Typography) private var typography

    let headers: [String]
    let rows: [[String]]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: true) {
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    ForEach(Array(headers.enumerated()), id: \.offset) { _, header in
                        cell(header, isHeader: true)
                    }
                }
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: 0) {
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
