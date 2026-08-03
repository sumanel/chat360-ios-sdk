import SwiftUI

/// Decorative only - mirrors `Hyundai_v1.html`'s Assistant Mode toggle, but there's no `mode`
/// concept anywhere in `Chat360Config`/`SessionInitResponse`/the WS wire protocol, so picking a
/// mode here doesn't change anything about the session. Local `@State`, not persisted.
private enum AssistantMode {
    case training
    case customer
}

/// Side drawer opened from the header's hamburger button (`Hyundai_v1.html`'s `.drawer` /
/// `.scrim`). Chat360 is single-room-per-session with no multi-conversation history endpoint
/// (see .claude/duplicate-welcome-message-rca.md and
/// design/Hyundai_v1_implementation_plan.md §4), so the chat list always shows the prototype's own
/// empty-history copy rather than a fake or placeholder list. The prototype's Menu panel (nav
/// items) is still out of scope - that's host-app navigation, see
/// design/Hyundai_v1_implementation_plan.md §0.
///
/// New Chat button / Assistant Mode / Appearance styling (font, weight, size, color, spacing)
/// ported 1:1 from `.new-chat-btn` / `.theme-row-label` / `.appearance-label` / `.theme-toggle` /
/// `.theme-opt` / `.theme-opt.selected` / `.drawer-footer` in design/Hyundai_v1.html.
struct ChatDrawer: View {
    var onNewChat: () -> Void
    /// Owned by `Chat360ChatSession` (not local to this view) so the choice survives the drawer
    /// closing/reopening - `nil` means "follow the system setting", same as today.
    @Binding var appearanceOverride: ColorScheme?

    @Environment(\.chat360Colors) private var colors
    @Environment(\.chat360Typography) private var typography

    @State private var assistantMode: AssistantMode = .customer

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Chats")
                .font(headFont(size: 17, weight: .semibold))
                .foregroundColor(colors.textPrimary)
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 16)

            Rectangle()
                .fill(colors.line)
                .frame(height: 1)

            // .new-chat-btn: margin 4px 14px 10px, bg accent, white text, Hyundai Sans Head 600 13.5px, padding 11, square corners.
            Button(action: onNewChat) {
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                    Text("New chat")
                }
                .font(headFont(size: 13.5, weight: .semibold))
                .foregroundColor(colors.accentContrast)
                .frame(maxWidth: .infinity)
                .padding(11)
                .background(colors.accent)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 14)
            .padding(.top, 4)
            .padding(.bottom, 10)

            VStack(spacing: 4) {
                Text("No conversations found.")
                Text("Try a different search, or start a new chat.")
            }
            .font(textFont(size: 13))
            .foregroundColor(colors.textSecondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
            .padding(.top, 36)

            Spacer()

            // .drawer-footer: border-top 1px line, padding 12px 14px 18px.
            VStack(alignment: .leading, spacing: 0) {
                footerRow(label: "Assistant Mode", topDivider: false) {
                    toggleButton("Training", icon: "graduationcap", selected: assistantMode == .training) { assistantMode = .training }
                    toggleButton("Customer", icon: "headphones", selected: assistantMode == .customer) { assistantMode = .customer }
                }
                footerRow(label: "Appearance", topDivider: true) {
                    toggleButton("Light", icon: "sun.max", selected: appearanceOverride == .light) { appearanceOverride = .light }
                    toggleButton("Dark", icon: "moon.fill", selected: appearanceOverride == .dark) { appearanceOverride = .dark }
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 18)
            .overlay(Rectangle().fill(colors.line).frame(height: 1), alignment: .top)
        }
        .frame(maxWidth: 300, maxHeight: .infinity, alignment: .leading)
        .background(colors.backgroundElevated)
    }

    // .theme-row-label (+ .appearance-label's extra top divider/margin for the second row).
    private func footerRow<Content: View>(label: String, topDivider: Bool, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if topDivider {
                Rectangle().fill(colors.line).frame(height: 1)
                    .padding(.top, 14)
            }
            Text(label)
                .font(headFont(size: 11, weight: .semibold))
                .kerning(0.4)
                .foregroundColor(colors.textSecondary)
                .padding(.horizontal, 6)
                .padding(.top, topDivider ? 14 : 2)
                .padding(.bottom, 8)
            // .theme-toggle: flex row, bg-sunken, padding 4, gap 4, square corners.
            HStack(spacing: 4) {
                content()
            }
            .padding(4)
            .background(colors.backgroundSunken)
        }
    }

    // .theme-opt / .theme-opt.selected: flex:1, Hyundai Sans Head 600 12.5px, 7px icon-label gap,
    // padding 9px vertical, no border, transparent when unselected; selected gets bg-elevated + accent text.
    private func toggleButton(_ title: String, icon: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                Text(title)
            }
            .font(headFont(size: 12.5, weight: .semibold))
            .foregroundColor(selected ? colors.accent : colors.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(selected ? colors.backgroundElevated : Color.clear)
        }
        .buttonStyle(.plain)
    }

    private func headFont(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        if let name = typography.headFontName { return .custom(name, size: size).weight(weight) }
        return .system(size: size, weight: weight)
    }

    private func textFont(size: CGFloat) -> Font {
        if let name = typography.textFontName { return .custom(name, size: size) }
        return .system(size: size)
    }
}
