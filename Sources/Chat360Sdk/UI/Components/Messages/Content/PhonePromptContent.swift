import SwiftUI

/// Ports the international PHONE variant only - a plain (non-international) PHONE node has no
/// dedicated widget or validation in the source either, so `BotContentBody` never routes here for
/// it; the always-visible bottom input bar answers it as free text.
struct PhonePromptContent: View {
    var message: ChatMessage
    var content: BotContent.PhonePrompt
    var isLiveChat: Bool
    var onValueChange: (_ primary: String, _ secondary: String) -> Void
    var onSubmit: () -> Void

    @Environment(\.chat360Colors) private var colors
    @Environment(\.chat360Typography) private var typography

    private var state: PromptState { message.promptState ?? PromptState() }
    private var fieldsEnabled: Bool { !state.submitted && !isLiveChat }
    private var countryCode: String { state.value }
    private var nationalNumber: String { state.secondaryValue }
    private var touched: Bool { !countryCode.isEmpty && !nationalNumber.isEmpty }
    private var isValid: Bool { touched && InputValidators.validatePhoneNumber(countryCode + nationalNumber, international: true) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            PlainTextContent(text: message.text)
            Spacer().frame(height: 6)
            HStack(spacing: 8) {
                TextField("+91", text: Binding(get: { countryCode }, set: { onValueChange($0, nationalNumber) }))
                    .keyboardType(.phonePad)
                    .disabled(!fieldsEnabled)
                    .padding(10)
                    .frame(width: 90)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(colors.inputBorder, lineWidth: 1))

                TextField("Phone number", text: Binding(get: { nationalNumber }, set: { onValueChange(countryCode, $0) }))
                    .keyboardType(.phonePad)
                    .disabled(!fieldsEnabled)
                    .padding(10)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(touched && !isValid ? formErrorColorPhone : colors.inputBorder, lineWidth: 1))
            }
            if touched && !isValid {
                Text("Please enter a valid phone number").font(textFont(size: 12)).foregroundColor(formErrorColorPhone)
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

private let formErrorColorPhone = Color(red: 0xDC / 255, green: 0x26 / 255, blue: 0x26 / 255)
