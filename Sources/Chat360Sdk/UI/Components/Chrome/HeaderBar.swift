import SwiftUI

/// `assignedAgent` mirrors the header's name/status swap once a human agent is assigned - this
/// header has no persistent bot-name/avatar area to swap, so it's surfaced as a status line
/// instead; the per-message name/avatar swap lives in `BotMessageRow`.
///
/// `onMenuTap` has no drawer to open yet (chat360 is single-room-per-session with no
/// multi-conversation history endpoint - see design/Hyundai_v1_implementation_plan.md §4) - the
/// button exists so a drawer can be wired in later without another header change.
struct HeaderBar: View {
    var connected: Bool
    var assignedAgent: AssignedAgent?
    var onMenuTap: () -> Void = {}
    var onNewSession: () -> Void = {}

    @Environment(\.chat360Colors) private var colors
    @Environment(\.chat360Typography) private var typography

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onMenuTap) {
                Image(systemName: "line.3.horizontal")
                    .foregroundColor(colors.textPrimary)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)

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

            Button(action: onNewSession) {
                Image(systemName: "plus")
                    .foregroundColor(colors.textPrimary)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 10)
    }

    private func textFont(size: CGFloat) -> Font {
        if let name = typography.textFontName { return .custom(name, size: size) }
        return .system(size: size)
    }
}
