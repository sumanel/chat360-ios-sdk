import SwiftUI

/// `assignedAgent` mirrors the header's name/status swap once a human agent is assigned - this
/// header has no persistent bot-name/avatar area to swap, so it's surfaced as a status line
/// instead; the per-message name/avatar swap lives in `BotMessageRow`.
///
/// No menu/new-chat icons here: chat360 is single-room-per-session with no multi-conversation
/// history endpoint, so there was nothing real to wire them to.
struct HeaderBar: View {
    var connected: Bool
    var assignedAgent: AssignedAgent?

    @Environment(\.chat360Colors) private var colors
    @Environment(\.chat360Typography) private var typography

    var body: some View {
        ZStack {
            let agentName = assignedAgent?.name?.trimmingCharacters(in: .whitespaces)
            if !connected {
                Text("connecting…")
                    .font(textFont(size: 12))
                    .foregroundColor(colors.textSecondary)
            } else if let agentName, !agentName.isEmpty {
                Text("Connected with \(agentName)")
                    .font(textFont(size: 12))
                    .foregroundColor(colors.textSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 8)
        .padding(.vertical, 10)
    }

    private func textFont(size: CGFloat) -> Font {
        if let name = typography.textFontName { return .custom(name, size: size) }
        return .system(size: size)
    }
}
