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

    private let onDismiss: () -> Void
    private let onNewChat: () -> Void
    private let isTrainingMode: Bool
    private let onAssistantModeChanged: (Bool) -> Void
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

    public init(
        onDismiss: @escaping () -> Void,
        onNewChat: @escaping () -> Void,
        isTrainingMode: Bool,
        onAssistantModeChanged: @escaping (Bool) -> Void,
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
        onLanguageSelected: @escaping (String) -> Void = { _ in }
    ) {
        self.onDismiss = onDismiss
        self.onNewChat = onNewChat
        self.isTrainingMode = isTrainingMode
        self.onAssistantModeChanged = onAssistantModeChanged
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
            }
            .padding(.horizontal, 20)
            .frame(height: 60)
            .overlay(Rectangle().frame(height: 1).foregroundColor(colors.line), alignment: .bottom)

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
                Spacer().frame(height: 28)

                if conversations.isEmpty {
                    Text("No saved conversations yet")
                        .font(typography.textFamily.font(size: 14))
                        .foregroundColor(colors.textSecondary)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(groupedConversations(conversations), id: \.label) { group in
                                HistoryGroup(
                                    title: group.label,
                                    items: group.items,
                                    activeConversationId: activeConversationId,
                                    onConversationSelected: onConversationSelected,
                                    onConversationRenamed: onConversationRenamed,
                                    onConversationDeleted: onConversationDeleted
                                )
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .frame(maxHeight: .infinity, alignment: .top)

            VStack(alignment: .leading, spacing: 0) {
                if showAssistantMode {
                    Text("Assistant Mode")
                        .font(typography.textFamily.font(size: 13, weight: .semibold))
                        .foregroundColor(colors.textSecondary)
                    Spacer().frame(height: 12)
                    HStack {
                        ModeOption(text: "Training", icon: .training, selected: isTrainingMode, disabled: true) { onAssistantModeChanged(true) }
                        ModeOption(text: "Customer", icon: .person, selected: !isTrainingMode, disabled: false) { onAssistantModeChanged(false) }
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
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .overlay(Rectangle().frame(height: 1).foregroundColor(colors.line), alignment: .top)
        }
        .frame(maxHeight: .infinity)
        .background(colors.backgroundElevated)
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
private struct HistoryGroup: View {
    @Environment(\.chat360Colors) private var colors
    @Environment(\.chat360Typography) private var typography
    let title: String
    let items: [CachedConversationEntity]
    let activeConversationId: String?
    let onConversationSelected: (String) -> Void
    let onConversationRenamed: (String, String) -> Void
    let onConversationDeleted: (String) -> Void

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
                        isActive: conversation.id == activeConversationId,
                        onSelected: { onConversationSelected(conversation.id) },
                        onRenamed: { onConversationRenamed(conversation.id, $0) },
                        onDeleted: { onConversationDeleted(conversation.id) }
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
    let isActive: Bool
    let onSelected: () -> Void
    let onRenamed: (String) -> Void
    let onDeleted: () -> Void

    @State private var showRenameDialog = false
    @State private var showDeleteDialog = false
    @State private var title = ""

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
                Button("Rename") { title = displayTitle; showRenameDialog = true }
                Button("Delete", role: .destructive) { showDeleteDialog = true }
            } label: {
                Chat360Icon.more.image.foregroundColor(colors.textSecondary)
            }
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(isActive ? colors.backgroundSunken : colors.backgroundElevated)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.bottom, 4)
        .alert("Rename conversation", isPresented: $showRenameDialog) {
            TextField("Conversation name", text: $title)
            Button("Save") { onRenamed(title) }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Delete conversation", isPresented: $showDeleteDialog) {
            Button("Delete", role: .destructive) { onDeleted() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This can't be undone. Delete \"\(displayTitle)\"?")
        }
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
