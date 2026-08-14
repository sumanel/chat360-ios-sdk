import SwiftUI

@available(iOS 15.0, *)
public struct TimePromptContent: View {
    @Environment(\.chat360Colors) private var colors

    private let message: ChatMessage
    private let content: BotContent.TimePrompt
    private let isLiveChat: Bool
    private let onSubmit: (String) -> Void

    @State private var hour = 9
    @State private var minute = 0
    @State private var isPm = false

    public init(message: ChatMessage, content: BotContent.TimePrompt, isLiveChat: Bool, onSubmit: @escaping (String) -> Void) {
        self.message = message
        self.content = content
        self.isLiveChat = isLiveChat
        self.onSubmit = onSubmit
    }

    private var state: PromptState { message.promptState ?? PromptState() }
    private var fieldsEnabled: Bool { !state.submitted && !isLiveChat }

    private func to24Hour(_ hour12: Int, _ isPm: Bool) -> Int {
        let h = hour12 % 12
        return isPm ? h + 12 : h
    }

    private func isBeforeNow() -> Bool {
        var calendar = Calendar.current
        let now = Date()
        let nowComponents = calendar.dateComponents([.hour, .minute], from: now)
        let selectedMinutes = to24Hour(hour, isPm) * 60 + minute
        let nowMinutes = (nowComponents.hour ?? 0) * 60 + (nowComponents.minute ?? 0)
        return selectedMinutes < nowMinutes
    }

    private var isValid: Bool {
        let slotBlocked = content.disabledSlots[hour]?.contains(minute) ?? false
        let pastBlocked = content.disablePrevious && isBeforeNow()
        return !slotBlocked && !pastBlocked
    }

    private func formatTime() -> String {
        String(format: "%02d : %02d %@", hour, minute, isPm ? "PM" : "AM")
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PlainTextContent(message.text)
            Spacer().frame(height: 10)
            HStack {
                Stepper(value: hour, range: 1...12, enabled: fieldsEnabled) { hour = $0 }
                Text(":").fontWeight(.bold).foregroundColor(colors.textPrimary).frame(width: 16)
                Stepper(value: minute, range: 0...59, enabled: fieldsEnabled, pad: true) { minute = $0 }
                Spacer().frame(width: 12)
                QuickReplyButton(text: "AM", enabled: fieldsEnabled, selected: !isPm) { isPm = false }
                Spacer().frame(width: 6)
                QuickReplyButton(text: "PM", enabled: fieldsEnabled, selected: isPm) { isPm = true }
            }
            if !isValid {
                Spacer().frame(height: 6)
                Text("This time slot is not available").foregroundColor(colors.textDisabled)
            }
            Spacer().frame(height: 10)
            Button(action: { onSubmit(formatTime()) }) {
                Text(state.submitted ? "Sent" : "Submit")
                    .foregroundColor(colors.accentContrast)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background((isValid && fieldsEnabled) ? colors.accent : colors.textDisabled)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .disabled(!(isValid && fieldsEnabled))
        }
    }
}

@available(iOS 15.0, *)
private struct Stepper: View {
    @Environment(\.chat360Colors) private var colors
    let value: Int
    let range: ClosedRange<Int>
    let enabled: Bool
    var pad: Bool = false
    let onChange: (Int) -> Void

    var body: some View {
        HStack {
            Button("-") { onChange(min(max(value - 1, range.lowerBound), range.upperBound)) }
                .foregroundColor(colors.accent)
                .disabled(!enabled)
            Text(pad ? String(format: "%02d", value) : String(value)).foregroundColor(colors.textPrimary)
            Button("+") { onChange(min(max(value + 1, range.lowerBound), range.upperBound)) }
                .foregroundColor(colors.accent)
                .disabled(!enabled)
        }
    }
}
