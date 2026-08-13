import SwiftUI

@available(iOS 13.0, *)
public let liveDotColor = Color(red: 0x22 / 255, green: 0xC5 / 255, blue: 0x5E / 255)

@available(iOS 15.0, *)
public struct AgentTransferNoticeContent: View {
    @Environment(\.chat360Typography) private var typography
    private let text: String

    public init(text: String) {
        self.text = text
    }

    public var body: some View {
        HStack(alignment: .center, spacing: 6) {
            Circle().fill(liveDotColor).frame(width: 6, height: 6)
            Text(text.isBlank ? "You are now connected with an agent." : text)
                .font(typography.textFamily.font(size: 12))
                .foregroundColor(liveDotColor)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(liveDotColor.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}
