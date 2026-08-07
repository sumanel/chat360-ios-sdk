import SwiftUI

/// `assignedAgent` mirrors the header's name/status swap once a human agent is assigned - this
/// header has no persistent bot-name/avatar area to swap, so it's surfaced as a status line
/// instead; the per-message name/avatar swap lives in `BotMessageRow`.
///
/// `onMenuTap` opens `ChatDrawer`'s conversation list/settings; `shortcuts` (from session-init's
/// `bot_settings.bot_shortcuts`) renders as a menu next to it when non-empty.
struct HeaderBar: View {
    var connected: Bool
    var assignedAgent: AssignedAgent?
    var shortcuts: [SessionShortcut] = []
    var onMenuTap: () -> Void = {}
    var onNewSession: () -> Void = {}
    var onShortcutSelected: (SessionShortcut) -> Void = { _ in }
    /// Manual refresh/reconnect - bypasses the automatic backoff, reuses the current room.
    var onReconnectTap: () -> Void = {}

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

            // Order matches Android's HeaderBar: refresh, then shortcuts, then new-chat.
            Button(action: onReconnectTap) {
                Image(systemName: "arrow.clockwise")
                    // Dimmed while connected (nothing to fix), full-strength while not - the same
                    // "something's wrong, tap to retry" affordance Android's refresh icon gives.
                    .foregroundColor(connected ? colors.textSecondary : colors.textPrimary)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)

            if !shortcuts.isEmpty {
                Menu {
                    ForEach(shortcuts) { shortcut in
                        Button(shortcut.label) { onShortcutSelected(shortcut) }
                    }
                } label: {
                    Image(systemName: "bolt")
                        .foregroundColor(colors.textPrimary)
                        .frame(width: 32, height: 32)
                }
            }

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
