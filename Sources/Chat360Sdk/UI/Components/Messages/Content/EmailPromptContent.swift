import SwiftUI

private let formErrorColor = Color(red: 0xDC / 255, green: 0x26 / 255, blue: 0x26 / 255)

/// Required + validateTest ("Test" word) + validateEmail format check.
struct EmailPromptContent: View {
    var message: ChatMessage
    var isLiveChat: Bool
    var onValueChange: (_ value: String, _ secondary: String) -> Void
    var onSubmit: () -> Void

    @Environment(\.chat360Colors) private var colors
    @Environment(\.chat360Typography) private var typography

    private var state: PromptState { message.promptState ?? PromptState() }
    private var fieldsEnabled: Bool { !state.submitted && !isLiveChat }

    private var errorText: String? {
        let value = state.value
        if value.isEmpty { return nil }
        if InputValidators.validateTest(value) { return "Email cannot contain the word 'Test'" }
        if !InputValidators.validateEmail(value) { return "Please enter a valid email address" }
        return nil
    }

    private var isValid: Bool { !state.value.isEmpty && errorText == nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            PlainTextContent(text: message.text)
            Spacer().frame(height: 6)
            TextField("you@example.com", text: Binding(get: { state.value }, set: { onValueChange($0, "") }))
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .disabled(!fieldsEnabled)
                .padding(10)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(errorText != nil ? formErrorColor : colors.inputBorder, lineWidth: 1))

            if let errorText {
                Text(errorText).font(textFont(size: 12)).foregroundColor(formErrorColor)
            }
            Spacer().frame(height: 6)
            Button(action: onSubmit) {
                Text(state.submitted ? "Sent" : "Submit")
                    .font(textFont(size: 14))
                    .fontWeight(.medium)
                    .foregroundColor(colors.accentContrast)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(isValid && fieldsEnabled ? colors.accent : colors.textDisabled)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .disabled(!(isValid && fieldsEnabled))
        }
    }

    private func textFont(size: CGFloat) -> Font {
        if let name = typography.textFontName { return .custom(name, size: size) }
        return .system(size: size)
    }
}
