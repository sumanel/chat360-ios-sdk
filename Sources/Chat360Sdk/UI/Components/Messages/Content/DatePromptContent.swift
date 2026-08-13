import SwiftUI

@available(iOS 15.0, *)
public struct DatePromptContent: View {
    @Environment(\.chat360Colors) private var colors

    private let message: ChatMessage
    private let content: BotContent.DatePrompt
    private let isLiveChat: Bool
    private let onDateSelected: (String) -> Void

    @State private var showDialog = false
    @State private var pickedDate = Date()
    @State private var errorText: String?

    public init(message: ChatMessage, content: BotContent.DatePrompt, isLiveChat: Bool, onDateSelected: @escaping (String) -> Void) {
        self.message = message
        self.content = content
        self.isLiveChat = isLiveChat
        self.onDateSelected = onDateSelected
    }

    private var state: PromptState { message.promptState ?? PromptState() }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PlainTextContent(message.text)
            Spacer().frame(height: 10)
            Button(action: { showDialog = true }) {
                Text(state.value.isBlank ? "Select a date" : state.value)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .foregroundColor(colors.accent)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(colors.accent, lineWidth: 1))
            }
            .disabled(state.submitted || isLiveChat)
        }
        .sheet(isPresented: $showDialog) {
            VStack {
                DatePicker("", selection: $pickedDate, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                if let errorText {
                    Text(errorText).foregroundColor(activeRed).font(.caption)
                }
                HStack {
                    Button("Cancel") { showDialog = false }
                    Spacer()
                    Button("OK") {
                        var calendar = Calendar(identifier: .gregorian)
                        calendar.timeZone = TimeZone(identifier: "UTC")!
                        let components = calendar.dateComponents([.year, .month, .day], from: pickedDate)
                        let simpleDate = SimpleDate(year: components.year!, month: components.month!, day: components.day!)
                        if DateAvailability.isDisabled(content.rules, date: simpleDate) {
                            errorText = "This date isn't available"
                        } else {
                            onDateSelected(DateAvailability.format(simpleDate, pattern: content.rules.dateFormat))
                            showDialog = false
                        }
                    }
                }
                .padding()
            }
            .padding()
        }
    }
}
