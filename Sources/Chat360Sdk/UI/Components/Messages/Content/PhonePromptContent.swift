import SwiftUI

@available(iOS 15.0, *)
public struct PhonePromptContent: View {
    @Environment(\.chat360Colors) private var colors
    @Environment(\.chat360Typography) private var typography

    private let message: ChatMessage
    private let content: BotContent.PhonePrompt
    private let isLiveChat: Bool
    private let onValueChange: (String, String) -> Void
    private let onSubmit: () -> Void

    public init(message: ChatMessage, content: BotContent.PhonePrompt, isLiveChat: Bool, onValueChange: @escaping (String, String) -> Void, onSubmit: @escaping () -> Void) {
        self.message = message
        self.content = content
        self.isLiveChat = isLiveChat
        self.onValueChange = onValueChange
        self.onSubmit = onSubmit
    }

    private var state: PromptState { message.promptState ?? PromptState() }
    private var fieldsEnabled: Bool { !state.submitted && !isLiveChat }
    private var touched: Bool { !state.value.isBlank && !state.secondaryValue.isBlank }
    private var isValid: Bool { touched && InputValidators.validatePhoneNumber(state.value + state.secondaryValue, international: true) }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PlainTextContent(message.text)
            Spacer().frame(height: 10)
            HStack {
                TextField("+91", text: Binding(get: { state.value }, set: { onValueChange($0, state.secondaryValue) }))
                    .font(typography.textFamily.font(size: 15))
                    .foregroundColor(colors.textPrimary)
                    .disabled(!fieldsEnabled)
                    .keyboardType(.phonePad)
                    .padding(12)
                    .frame(width: 90)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(colors.inputBorder, lineWidth: 1))
                Spacer().frame(width: 8)
                TextField("Phone number", text: Binding(get: { state.secondaryValue }, set: { onValueChange(state.value, $0) }))
                    .font(typography.textFamily.font(size: 15))
                    .foregroundColor(colors.textPrimary)
                    .disabled(!fieldsEnabled)
                    .keyboardType(.phonePad)
                    .padding(12)
                    .frame(maxWidth: .infinity)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke((touched && !isValid) ? promptErrorColor : colors.inputBorder, lineWidth: 1))
            }
            if touched && !isValid {
                Spacer().frame(height: 4)
                Text("Please enter a valid phone number").font(typography.textFamily.font(size: 12)).foregroundColor(promptErrorColor)
            }
            Spacer().frame(height: 10)
            Button(action: onSubmit) {
                Text(state.submitted ? "Sent" : "Submit")
                    .font(typography.textFamily.font(size: 15, weight: .medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .foregroundColor(colors.accentContrast)
                    .background((isValid && fieldsEnabled) ? colors.accent : colors.textDisabled)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .disabled(!(isValid && fieldsEnabled))
        }
    }
}
