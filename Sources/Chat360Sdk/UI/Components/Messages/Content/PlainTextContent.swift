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
        if !text.isEmpty {
            Text(text.toAttributedString(linkColor: colors.accent))
                .font(typography.textFamily.font(size: 15))
                .lineSpacing(7)
                .foregroundColor(colors.bubbleAiText)
        }
    }
}
