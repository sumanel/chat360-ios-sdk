import SwiftUI
import Foundation

/// Ports the standalone TIME node: hour/minute steppers (12-hour) + AM/PM, blocked by disabledSlots.
struct TimePromptContent: View {
    var message: ChatMessage
    var content: BotContent.TimePrompt
    var isLiveChat: Bool
    var onSubmit: (String) -> Void

    @Environment(\.chat360Colors) private var colors
    @Environment(\.chat360Typography) private var typography
    @State private var hour = 9
    @State private var minute = 0
    @State private var isPm = false

    private var state: PromptState { message.promptState ?? PromptState() }
    private var fieldsEnabled: Bool { !state.submitted && !isLiveChat }

    private var slotBlocked: Bool { content.disabledSlots[hour]?.contains(minute) ?? false }
    private var pastBlocked: Bool { content.disablePrevious && isBeforeNow(hour: hour, minute: minute, isPm: isPm) }
    private var isValid: Bool { !slotBlocked && !pastBlocked }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            PlainTextContent(text: message.text)
            Spacer().frame(height: 6)
            HStack(spacing: 12) {
                stepper(value: hour, onChange: { hour = min(max($0, 1), 12) })
                Text(":").fontWeight(.bold).foregroundColor(colors.textPrimary)
                stepper(value: minute, onChange: { minute = min(max($0, 0), 59) }, pad: true)
                QuickReplyButton(text: "AM", enabled: fieldsEnabled, selected: !isPm, onTap: { isPm = false })
                QuickReplyButton(text: "PM", enabled: fieldsEnabled, selected: isPm, onTap: { isPm = true })
            }
            if !isValid {
                Text("This time slot is not available").font(textFont(size: 13)).foregroundColor(colors.textDisabled)
            }
            Spacer().frame(height: 6)
            Button(action: { onSubmit(formatTime(hour: hour, minute: minute, isPm: isPm)) }) {
                Text(state.submitted ? "Sent" : "Submit")
                    .font(textFont(size: 14))
                    .foregroundColor(colors.accentContrast)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(isValid && fieldsEnabled ? colors.accent : colors.textDisabled)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .disabled(!(isValid && fieldsEnabled))
        }
    }

    private func stepper(value: Int, onChange: @escaping (Int) -> Void, pad: Bool = false) -> some View {
        HStack(spacing: 4) {
            Button(action: { onChange(value - 1) }) { Text("-").foregroundColor(colors.accent) }
                .disabled(!fieldsEnabled)
            Text(pad ? String(format: "%02d", value) : String(value)).foregroundColor(colors.textPrimary)
            Button(action: { onChange(value + 1) }) { Text("+").foregroundColor(colors.accent) }
                .disabled(!fieldsEnabled)
        }
    }

    private func to24Hour(hour12: Int, isPm: Bool) -> Int {
        let h = hour12 % 12
        return isPm ? h + 12 : h
    }

    private func isBeforeNow(hour: Int, minute: Int, isPm: Bool) -> Bool {
        let calendar = Calendar.current
        let now = Date()
        let nowComponents = calendar.dateComponents([.hour, .minute], from: now)
        let selectedMinutes = to24Hour(hour12: hour, isPm: isPm) * 60 + minute
        let nowMinutes = (nowComponents.hour ?? 0) * 60 + (nowComponents.minute ?? 0)
        return selectedMinutes < nowMinutes
    }

    private func formatTime(hour: Int, minute: Int, isPm: Bool) -> String {
        String(format: "%02d : %02d %@", hour, minute, isPm ? "PM" : "AM")
    }

    private func textFont(size: CGFloat) -> Font {
        if let name = typography.textFontName { return .custom(name, size: size) }
        return .system(size: size)
    }
}
