import SwiftUI

@available(iOS 14.0, *)
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
        onCloseClick: (() -> Void)? = nil
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
