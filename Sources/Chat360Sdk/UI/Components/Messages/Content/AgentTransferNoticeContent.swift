import SwiftUI

private let liveDotColor = Color(red: 0x22 / 255, green: 0xC5 / 255, blue: 0x5E / 255)

/// A small pill announcing the handoff to a human agent.
struct AgentTransferNoticeContent: View {
    var text: String

    @Environment(\.chat360Typography) private var typography

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(liveDotColor).frame(width: 6, height: 6)
            Text(text.isEmpty ? "You are now connected with an agent." : text)
                .font(textFont(size: 12))
                .foregroundColor(liveDotColor)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(liveDotColor.opacity(0.08))
        .clipShape(Capsule())
    }

    private func textFont(size: CGFloat) -> Font {
        if let name = typography.textFontName { return .custom(name, size: size) }
        return .system(size: size)
    }
}
