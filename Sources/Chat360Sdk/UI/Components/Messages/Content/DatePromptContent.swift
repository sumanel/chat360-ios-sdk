import SwiftUI

/// Ports the standalone DATE node - a button opening a calendar, submitting the pick immediately.
/// SwiftUI's `DatePicker` (unlike Compose's Material3 one) has no per-day enable/disable hook, so
/// disabled dates are enforced on confirm instead of grayed out in the calendar itself.
struct DatePromptContent: View {
    var message: ChatMessage
    var content: BotContent.DatePrompt
    var isLiveChat: Bool
    var onDateSelected: (String) -> Void

    @Environment(\.chat360Colors) private var colors
    @Environment(\.chat360Typography) private var typography
    @State private var showPicker = false
    @State private var pickedDate = Date()
    @State private var disabledError = false

    private var state: PromptState { message.promptState ?? PromptState() }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            PlainTextContent(text: message.text)
            Spacer().frame(height: 6)
            Button(action: { showPicker = true }) {
                Text(state.value.isEmpty ? "Select a date" : state.value)
                    .font(textFont(size: 14))
                    .foregroundColor(colors.accent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(colors.accent, lineWidth: 1))
            }
            .disabled(state.submitted || isLiveChat)
            if disabledError {
                Text("That date isn't available").font(textFont(size: 12)).foregroundColor(.red)
            }
        }
        .sheet(isPresented: $showPicker) {
            VStack {
                DatePicker("", selection: $pickedDate, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .padding()
                HStack {
                    Button("Cancel") { showPicker = false }
                    Spacer()
                    Button("OK") {
                        let selected = SimpleDate(date: pickedDate)
                        if DateAvailability.isDisabled(content.rules, selected) {
                            disabledError = true
                        } else {
                            disabledError = false
                            onDateSelected(DateAvailability.format(selected, pattern: content.rules.dateFormat))
                            showPicker = false
                        }
                    }
                }
                .padding()
            }
        }
    }

    private func textFont(size: CGFloat) -> Font {
        if let name = typography.textFontName { return .custom(name, size: size) }
        return .system(size: size)
    }
}
