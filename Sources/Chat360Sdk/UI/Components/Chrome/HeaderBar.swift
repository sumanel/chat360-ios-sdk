import SwiftUI

@available(iOS 15.0, *)
public struct HeaderBar: View {
    @Environment(\.chat360Colors) private var colors

    private let connected: Bool
    private let assignedAgent: AssignedAgent?
    private let showMenu: Bool
    private let showNewChat: Bool
    private let newChatEnabled: Bool
    private let onMenuClick: () -> Void
    private let onNewChatClick: () -> Void
    private let shortcuts: [String: String]
    private let onShortcutSelected: (String, String) -> Void
    private let onRefreshClick: () -> Void
    private let onCloseClick: (() -> Void)?
    private let sessionTimerExpiresAt: Date?

    public init(
        connected: Bool,
        assignedAgent: AssignedAgent? = nil,
        showMenu: Bool = true,
        showNewChat: Bool = true,
        newChatEnabled: Bool = true,
        onMenuClick: @escaping () -> Void = {},
        onNewChatClick: @escaping () -> Void = {},
        shortcuts: [String: String] = [:],
        onShortcutSelected: @escaping (String, String) -> Void = { _, _ in },
        onRefreshClick: @escaping () -> Void = {},
        onCloseClick: (() -> Void)? = nil,
        sessionTimerExpiresAt: Date? = nil
    ) {
        self.connected = connected
        self.assignedAgent = assignedAgent
        self.showMenu = showMenu
        self.showNewChat = showNewChat
        self.newChatEnabled = newChatEnabled
        self.onMenuClick = onMenuClick
        self.onNewChatClick = onNewChatClick
        self.shortcuts = shortcuts
        self.onShortcutSelected = onShortcutSelected
        self.onRefreshClick = onRefreshClick
        self.onCloseClick = onCloseClick
        self.sessionTimerExpiresAt = sessionTimerExpiresAt
    }

    public var body: some View {
        HStack(spacing: 0) {
            if showMenu {
                Button(action: onMenuClick) {
                    Chat360Icon.menu.image
                        .foregroundColor(colors.textPrimary)
                        .frame(width: 24, height: 24)
                }
            }
            if !shortcuts.isEmpty {
                Spacer().frame(width: 16)
                Menu {
                    ForEach(shortcuts.sorted(by: { $0.key < $1.key }), id: \.key) { label, targetId in
                        Button(label) { onShortcutSelected(targetId, label) }
                    }
                } label: {
                    Chat360Icon.shortcut.image
                        .foregroundColor(colors.textPrimary)
                        .frame(width: 22, height: 22)
                }
            }
            Spacer()
            if let sessionTimerExpiresAt {
                SessionCountdownText(expiresAt: sessionTimerExpiresAt)
                    .padding(.trailing, showNewChat || onCloseClick != nil ? 14 : 0)
            }
            if showNewChat {
                Button(action: onNewChatClick) {
                    Chat360Icon.add.image
                        .foregroundColor(newChatEnabled ? colors.textPrimary : colors.textDisabled)
                        .frame(width: 24, height: 24)
                }
                .disabled(!newChatEnabled)
            }
            if let onCloseClick {
                if showNewChat {
                    Spacer().frame(width: 18)
                }
                Button(action: onCloseClick) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(colors.textPrimary)
                        .frame(width: 24, height: 24)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(colors.background)
    }
}

// Purely a display of `sessionTimerExpiresAt` - hides itself once expired rather than freezing
// at 0:00, since nothing here restarts it; that only happens on the next user message.
@available(iOS 15.0, *)
private struct SessionCountdownText: View {
    @Environment(\.chat360Colors) private var colors
    let expiresAt: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = expiresAt.timeIntervalSince(context.date)
            if remaining > 0 {
                let minutes = Int(remaining) / 60
                let seconds = Int(remaining) % 60
                Text(String(format: "%02d:%02d", minutes, seconds))
                    .font(.system(size: 13, weight: .medium).monospacedDigit())
                    .foregroundColor(colors.textSecondary)
            }
        }
    }
}
