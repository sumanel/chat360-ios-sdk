import SwiftUI

@available(iOS 15.0, *)
private func historyGroupLabel(for updatedAtMs: Int64) -> String {
    let date = Date(timeIntervalSince1970: Double(updatedAtMs) / 1000)
    let calendar = Calendar.current
    if calendar.isDateInToday(date) { return "Today" }
    if calendar.isDateInYesterday(date) { return "Yesterday" }
    let daysAgo = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: Date())).day ?? 0
    return daysAgo <= 7 ? "Last 7 Days" : "Older"
}

@available(iOS 15.0, *)
private func groupedConversations(_ conversations: [CachedConversationEntity]) -> [(label: String, items: [CachedConversationEntity])] {
    let order = ["Today", "Yesterday", "Last 7 Days", "Older"]
    let grouped = Dictionary(grouping: conversations, by: { historyGroupLabel(for: $0.updatedAt) })
    return order.compactMap { label in
        guard let items = grouped[label], !items.isEmpty else { return nil }
        return (label, items)
    }
}

@available(iOS 15.0, *)
public struct ChatDrawer: View {
    @Environment(\.chat360Colors) private var colors
    @Environment(\.chat360Typography) private var typography

    // Centralized here rather than one `.alert` per row (as it was before): SwiftUI only
    // reliably drives one alert-presentation source per view hierarchy, so with a separate
    // `.alert` attached to every `ConversationItem`, only whichever row's alert got claimed
    // first kept working - every other room's rename/delete silently stopped doing anything.
    @State private var pendingRename: (id: String, title: String)?
    @State private var pendingDelete: (id: String, title: String)?
    @State private var renameDraft: String = ""
    // Measured height of the two pinned blocks (history header + settings). What's left of the
    // panel goes to the scrollable conversation list.
    @State private var chromeHeight: CGFloat = 0

    private let onDismiss: () -> Void
    private let onNewChat: () -> Void
    private let assistantModes: [Chat360AssistantModeOption]
    private let selectedAssistantMode: Int
    private let onAssistantModeSelected: (Int) -> Void
    private let roomRoles: [String: String]
    private let isDarkTheme: Bool
    private let onThemeChanged: (Bool) -> Void
    private let showAssistantMode: Bool
    private let showAppearanceSwitcher: Bool
    private let conversations: [CachedConversationEntity]
    private let activeConversationId: String?
    private let onConversationSelected: (String) -> Void
    private let onConversationRenamed: (String, String) -> Void
    private let onConversationDeleted: (String) -> Void
    private let languages: [SessionLanguage]
    private let onLanguageSelected: (String) -> Void
    private let isHistoryUnavailable: Bool
    private let onRetryHistory: () -> Void
    private let hasMoreRooms: Bool
    private let isLoadingMoreRooms: Bool
    private let onLoadMoreRooms: () -> Void

    public init(
        onDismiss: @escaping () -> Void,
        onNewChat: @escaping () -> Void,
        assistantModes: [Chat360AssistantModeOption],
        selectedAssistantMode: Int,
        onAssistantModeSelected: @escaping (Int) -> Void,
        roomRoles: [String: String] = [:],
        isDarkTheme: Bool,
        onThemeChanged: @escaping (Bool) -> Void,
        showAssistantMode: Bool,
        showAppearanceSwitcher: Bool,
        conversations: [CachedConversationEntity],
        activeConversationId: String? = nil,
        onConversationSelected: @escaping (String) -> Void,
        onConversationRenamed: @escaping (String, String) -> Void,
        onConversationDeleted: @escaping (String) -> Void = { _ in },
        languages: [SessionLanguage] = [],
        onLanguageSelected: @escaping (String) -> Void = { _ in },
        isHistoryUnavailable: Bool = false,
        onRetryHistory: @escaping () -> Void = {},
        hasMoreRooms: Bool = false,
        isLoadingMoreRooms: Bool = false,
        onLoadMoreRooms: @escaping () -> Void = {}
    ) {
        self.onDismiss = onDismiss
        self.onNewChat = onNewChat
        self.assistantModes = assistantModes
        self.selectedAssistantMode = selectedAssistantMode
        self.onAssistantModeSelected = onAssistantModeSelected
        self.roomRoles = roomRoles
        self.isDarkTheme = isDarkTheme
        self.onThemeChanged = onThemeChanged
        self.showAssistantMode = showAssistantMode
        self.showAppearanceSwitcher = showAppearanceSwitcher
        self.conversations = conversations
        self.activeConversationId = activeConversationId
        self.onConversationSelected = onConversationSelected
        self.onConversationRenamed = onConversationRenamed
        self.onConversationDeleted = onConversationDeleted
        self.languages = languages
        self.onLanguageSelected = onLanguageSelected
        self.isHistoryUnavailable = isHistoryUnavailable
        self.onRetryHistory = onRetryHistory
        self.hasMoreRooms = hasMoreRooms
        self.isLoadingMoreRooms = isLoadingMoreRooms
        self.onLoadMoreRooms = onLoadMoreRooms
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button(action: onDismiss) {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 13, weight: .bold))
                        Text("Menu")
                            .font(typography.textFamily.font(size: 17, weight: .bold))
                    }
                    .foregroundColor(colors.accent)
                }
                Spacer()
                Text("v\(Constants.sdkVersion)")
                    .font(typography.textFamily.font(size: 12))
                    .foregroundColor(colors.textSecondary)
            }
            .padding(.horizontal, 20)
            .frame(height: 60)
            .overlay(Rectangle().frame(height: 1).foregroundColor(colors.line), alignment: .bottom)

            // Only the conversation list scrolls: the history header ("New chat") stays pinned
            // at the top and the settings block (Assistant Mode / Appearance / Language) stays
            // pinned at the bottom, so those controls don't move as saved conversations pile up.
            // The list gets whatever height is left between the two fixed blocks.
            //
            // On a short screen (landscape) that leftover can shrink below `minHistoryHeight` -
            // the fixed header + settings alone nearly fill the panel. Rather than collapse the
            // list to nothing, fall back to scrolling the whole area as one piece so the history
            // is still reachable.
            GeometryReader { geo in
                let historyHeight = geo.size.height - chromeHeight
                if chromeHeight > 0 && historyHeight < Self.minHistoryHeight {
                    ScrollView {
                        VStack(spacing: 0) {
                            historyHeader
                            historyList
                            settingsBlock
                        }
                    }
                } else {
                    VStack(spacing: 0) {
                        historyHeader
                        ScrollView { historyList }
                            .frame(height: max(historyHeight, Self.minHistoryHeight))
                        settingsBlock
                    }
                    .frame(maxHeight: .infinity, alignment: .top)
                }
            }
            .frame(maxHeight: .infinity)
            .onPreferenceChange(ChromeHeightKey.self) { chromeHeight = $0 }
        }
        .frame(maxHeight: .infinity)
        .background(colors.backgroundElevated)
        .alert(
            "Rename conversation",
            isPresented: Binding(get: { pendingRename != nil }, set: { if !$0 { pendingRename = nil } })
        ) {
            TextField("Conversation name", text: $renameDraft)
            Button("Save") {
                if let id = pendingRename?.id { onConversationRenamed(id, renameDraft) }
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert(
            "Delete conversation",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })
        ) {
            Button("Delete", role: .destructive) {
                if let id = pendingDelete?.id { onConversationDeleted(id) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This can't be undone. Delete \"\(pendingDelete?.title ?? "")\"?")
        }
    }

    /// Smallest height the conversation list is allowed before the layout stops pinning the
    /// header/settings and scrolls the whole panel instead (keeps ~2 rows visible).
    private static let minHistoryHeight: CGFloat = 140

    @ViewBuilder
    private var historyHeader: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("AI Chatbot - History")
                .font(typography.textFamily.font(size: 20, weight: .bold))
                .foregroundColor(colors.textPrimary)
            Spacer().frame(height: 16)
            Button(action: onNewChat) {
                HStack(spacing: 12) {
                    Chat360Icon.add.image.foregroundColor(colors.accentContrast)
                    Text("New chat")
                        .font(typography.textFamily.font(size: 17, weight: .bold))
                        .foregroundColor(colors.accentContrast)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 49)
                .background(colors.accent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 20)
        .background(GeometryReader { g in
            Color.clear.preference(key: ChromeHeightKey.self, value: g.size.height)
        })
    }

    @ViewBuilder
    private var historyList: some View {
        VStack(alignment: .leading, spacing: 0) {
            // The server list failed to load, so only chats cached on this device are shown.
            if isHistoryUnavailable {
                Button(action: onRetryHistory) {
                    Text("Couldn't load your older chats. Tap to retry.")
                        .font(typography.textFamily.font(size: 13))
                        .foregroundColor(colors.textSecondary)
                        .multilineTextAlignment(.leading)
                }
                .padding(.bottom, 16)
            }
            if conversations.isEmpty {
                Text("No saved conversations yet")
                    .font(typography.textFamily.font(size: 14))
                    .foregroundColor(colors.textSecondary)
            } else {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(groupedConversations(conversations), id: \.label) { group in
                        HistoryGroup(
                            title: group.label,
                            items: group.items,
                            activeConversationId: activeConversationId,
                            roleBadgeFor: { conversation in
                                guard showAssistantMode else { return nil }
                                return assistantModes.badge(forRole: conversation.roomId.flatMap { roomRoles[$0] })
                            },
                            onConversationSelected: onConversationSelected,
                            onRenameRequested: { id, title in
                                renameDraft = title
                                pendingRename = (id, title)
                            },
                            onDeleteRequested: { id, title in
                                pendingDelete = (id, title)
                            }
                        )
                    }
                }
            }
            if hasMoreRooms {
                Button(action: onLoadMoreRooms) {
                    Text(isLoadingMoreRooms ? "Loading…" : "Load more")
                        .font(typography.textFamily.font(size: 15, weight: .semibold))
                        .foregroundColor(colors.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
                .disabled(isLoadingMoreRooms)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
        .padding(.bottom, 16)
    }

    @ViewBuilder
    private var settingsBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showAssistantMode {
                Text("Assistant Mode")
                    .font(typography.textFamily.font(size: 13, weight: .semibold))
                    .foregroundColor(colors.textSecondary)
                Spacer().frame(height: 12)
                HStack {
                    ForEach(Array(assistantModes.enumerated()), id: \.offset) { index, option in
                        ModeOption(
                            text: option.label,
                            icon: index == 0 ? .training : .person,
                            selected: index == selectedAssistantMode,
                            disabled: !option.enabled
                        ) { onAssistantModeSelected(index) }
                    }
                }
                Spacer().frame(height: 18)
            }
            if showAppearanceSwitcher {
                Text("Appearance")
                    .font(typography.textFamily.font(size: 13, weight: .semibold))
                    .foregroundColor(colors.textSecondary)
                Spacer().frame(height: 12)
                HStack {
                    ModeOption(text: "Light", icon: .lightMode, selected: !isDarkTheme) { onThemeChanged(false) }
                    ModeOption(text: "Dark", icon: .darkMode, selected: isDarkTheme) { onThemeChanged(true) }
                }
            }
            if languages.count > 1 {
                Spacer().frame(height: 18)
                Text("LANGUAGE")
                    .font(typography.textFamily.font(size: 13, weight: .semibold))
                    .foregroundColor(colors.textSecondary)
                Spacer().frame(height: 12)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(languages, id: \.key) { language in
                            LanguageChip(label: language.value, selected: language.default) { onLanguageSelected(language.key) }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .overlay(Rectangle().frame(height: 1).foregroundColor(colors.line), alignment: .top)
        .background(GeometryReader { g in
            Color.clear.preference(key: ChromeHeightKey.self, value: g.size.height)
        })
    }
}

@available(iOS 15.0, *)
private struct ChromeHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value += nextValue()
    }
}

@available(iOS 15.0, *)
private struct LanguageChip: View {
    @Environment(\.chat360Colors) private var colors
    @Environment(\.chat360Typography) private var typography
    let label: String
    let selected: Bool
    let onClick: () -> Void

    var body: some View {
        Button(action: onClick) {
            Text(label)
                .font(typography.textFamily.font(size: 15, weight: .semibold))
                .foregroundColor(selected ? colors.accent : colors.textPrimary)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(selected ? colors.backgroundElevated : colors.backgroundSunken)
                .overlay(selected ? AnyView(Rectangle().stroke(colors.line, lineWidth: 1)) : AnyView(EmptyView()))
        }
    }
}

@available(iOS 15.0, *)
@available(iOS 15.0, *)
private struct HistoryGroup: View {
    @Environment(\.chat360Colors) private var colors
    @Environment(\.chat360Typography) private var typography
    let title: String
    let items: [CachedConversationEntity]
    let activeConversationId: String?
    let roleBadgeFor: (CachedConversationEntity) -> Chat360AssistantRoleBadge?
    let onConversationSelected: (String) -> Void
    let onRenameRequested: (String, String) -> Void
    let onDeleteRequested: (String, String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title.uppercased())
                .font(typography.textFamily.font(size: 11, weight: .semibold))
                .tracking(0.4)
                .foregroundColor(colors.textSecondary)
            Spacer().frame(height: 8)
            LazyVStack(spacing: 0) {
                ForEach(items, id: \.id) { conversation in
                    ConversationItem(
                        conversation: conversation,
                        roleBadge: roleBadgeFor(conversation),
                        isActive: conversation.id == activeConversationId,
                        onSelected: { onConversationSelected(conversation.id) },
                        onRenameRequested: { onRenameRequested(conversation.id, $0) },
                        onDeleteRequested: { onDeleteRequested(conversation.id, $0) }
                    )
                }
            }
            Spacer().frame(height: 6)
        }
    }
}

@available(iOS 15.0, *)
private func historyDateFormatter() -> DateFormatter {
    let formatter = DateFormatter()
    formatter.dateFormat = "MMM d, h:mm a"
    formatter.locale = Locale.current
    return formatter
}

@available(iOS 15.0, *)
private struct ConversationItem: View {
    @Environment(\.chat360Colors) private var colors
    @Environment(\.chat360Typography) private var typography

    let conversation: CachedConversationEntity
    let roleBadge: Chat360AssistantRoleBadge?
    let isActive: Bool
    let onSelected: () -> Void
    let onRenameRequested: (String) -> Void
    let onDeleteRequested: (String) -> Void

    private var displayTitle: String {
        if conversation.title == "New conversation" {
            return historyDateFormatter().string(from: Date(timeIntervalSince1970: Double(conversation.createdAt) / 1000))
        }
        return conversation.title
    }

    var body: some View {
        let itemColor = isActive ? colors.accent : colors.textPrimary
        HStack(alignment: .top, spacing: 14) {
            Button(action: onSelected) {
                HStack(alignment: .top, spacing: 14) {
                    Chat360Icon.chat.image.foregroundColor(isActive ? colors.accent : colors.textSecondary)
                        .overlay(alignment: .bottomTrailing) {
                            if let roleBadge {
                                (roleBadge.modeIndex == nil ? Chat360Icon.tag : (roleBadge.modeIndex == 0 ? Chat360Icon.training : Chat360Icon.person)).image
                                    .foregroundColor(colors.accent)
                                    .frame(width: 11, height: 11)
                                    .padding(1)
                                    .background(Circle().fill(isActive ? colors.backgroundSunken : colors.backgroundElevated))
                                    .offset(x: 4, y: 4)
                                    .accessibilityLabel(roleBadge.label)
                            }
                        }
                    VStack(alignment: .leading, spacing: 0) {
                        Text(displayTitle)
                            .font(typography.textFamily.font(size: 16, weight: .semibold))
                            .foregroundColor(itemColor)
                            .lineLimit(1)
                        Text(historyDateFormatter().string(from: Date(timeIntervalSince1970: Double(conversation.createdAt) / 1000)))
                            .font(typography.textFamily.font(size: 13))
                            .foregroundColor(colors.textSecondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Menu {
                Button("Rename") { onRenameRequested(displayTitle) }
                Button("Delete", role: .destructive) { onDeleteRequested(displayTitle) }
            } label: {
                Chat360Icon.more.image
                    .foregroundColor(colors.textSecondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(isActive ? colors.backgroundSunken : colors.backgroundElevated)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.bottom, 4)
    }
}

@available(iOS 15.0, *)
private struct ModeOption: View {
    @Environment(\.chat360Colors) private var colors
    @Environment(\.chat360Typography) private var typography
    let text: String
    let icon: Chat360Icon
    let selected: Bool
    let disabled: Bool
    let onClick: () -> Void

    init(text: String, icon: Chat360Icon, selected: Bool, disabled: Bool = false, onClick: @escaping () -> Void) {
        self.text = text
        self.icon = icon
        self.selected = selected
        self.disabled = disabled
        self.onClick = onClick
    }

    var body: some View {
        let contentColor = selected ? colors.accent : colors.textPrimary
        Button(action: onClick) {
            HStack(spacing: 8) {
                icon.image.foregroundColor(contentColor).frame(width: 18, height: 18)
                Text(text)
                    .font(typography.textFamily.font(size: 15, weight: .semibold))
                    .foregroundColor(contentColor)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(selected ? colors.backgroundElevated : colors.backgroundSunken)
            .overlay(selected ? AnyView(Rectangle().stroke(colors.line, lineWidth: 1)) : AnyView(EmptyView()))
        }
        .disabled(disabled)
        .opacity(disabled ? 0.4 : 1)
    }
}
