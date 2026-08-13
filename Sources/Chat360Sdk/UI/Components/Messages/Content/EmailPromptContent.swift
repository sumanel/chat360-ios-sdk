import SwiftUI

@available(iOS 15.0, *)
public let promptErrorColor = Color(red: 0xDC / 255, green: 0x26 / 255, blue: 0x26 / 255)

@available(iOS 15.0, *)
public struct EmailPromptContent: View {
    @Environment(\.chat360Colors) private var colors
    @Environment(\.chat360Typography) private var typography

    private let message: ChatMessage
    private let isLiveChat: Bool
    private let onValueChange: (String, String) -> Void
    private let onSubmit: () -> Void

    public init(message: ChatMessage, isLiveChat: Bool, onValueChange: @escaping (String, String) -> Void, onSubmit: @escaping () -> Void) {
        self.message = message
        self.isLiveChat = isLiveChat
        self.onValueChange = onValueChange
        self.onSubmit = onSubmit
    }

    private var state: PromptState { message.promptState ?? PromptState() }

    private var errorText: String? {
        let value = state.value
        if value.isBlank { return nil }
        if InputValidators.validateTest(value) { return "Email cannot contain the word 'Test'" }
        if !InputValidators.validateEmail(value) { return "Please enter a valid email address" }
        return nil
    }

    private var isValid: Bool { !state.value.isBlank && errorText == nil }
    private var fieldsEnabled: Bool { !state.submitted && !isLiveChat }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PlainTextContent(message.text)
            Spacer().frame(height: 10)
            TextField("you@example.com", text: Binding(get: { state.value }, set: { onValueChange($0, "") }))
                .font(typography.textFamily.font(size: 15))
                .foregroundColor(colors.textPrimary)
                .disabled(!fieldsEnabled)
                .keyboardType(.emailAddress)
                .autocapitalization(.none)
                .padding(12)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(errorText != nil ? promptErrorColor : colors.inputBorder, lineWidth: 1))
            if let errorText {
                Spacer().frame(height: 4)
                Text(errorText).font(typography.textFamily.font(size: 12)).foregroundColor(promptErrorColor)
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
