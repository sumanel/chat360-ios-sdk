import SwiftUI

private let formErrorColorForm = Color(red: 0xDC / 255, green: 0x26 / 255, blue: 0x26 / 255)

/// Renders the FORM field set (TEXT/NUMBER/EMAIL/PHONE/SELECT/DATE/MEDIA), with the exact per-field
/// validation matrix from `FormFieldValidator` (required, format, length/count bounds,
/// "Test"-word blocks, phone blocklist, alpha-only). Field types without a dedicated renderer
/// (RCS-specific, etc.) fall back to `.other` and render as a disabled placeholder row rather
/// than blocking the whole form.
struct FormContent: View {
    var message: ChatMessage
    var content: BotContent.Form
    var isLiveChat: Bool
    var onFieldChange: (_ fieldIndex: Int, _ value: String) -> Void
    var onPickMediaField: (_ fieldIndex: Int) -> Void
    var onSubmit: () -> Void

    @Environment(\.chat360Colors) private var colors
    @Environment(\.chat360Typography) private var typography
    @State private var showDatePickerForField: Int?
    @State private var pickedDate = Date()

    private var formState: FormState { message.formState ?? FormState() }
    private var submitted: Bool { formState.submitted }
    // Fields/submit disable (not hide) once live chat takes over too - kept separate from
    // `submitted` itself so the button still reads the real submit-state label.
    private var fieldsEnabled: Bool { !submitted && !isLiveChat }
    private var canSubmit: Bool { fieldsEnabled && formState.uploadingFields.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(content.fields, id: \.index) { field in
                fieldView(field)
                if let error = fieldError(field) {
                    Text(error).font(textFont(size: 12)).foregroundColor(formErrorColorForm)
                }
            }
            Button(action: onSubmit) {
                Text(submitted ? "Submitted" : content.submitButtonText)
                    .font(textFont(size: 14))
                    .fontWeight(.medium)
                    .foregroundColor(colors.accentContrast)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(canSubmit ? colors.accent : colors.textDisabled)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .disabled(!canSubmit)
        }
        .sheet(item: Binding(
            get: { showDatePickerForField.map { FieldIndexBox(index: $0) } },
            set: { showDatePickerForField = $0?.index }
        )) { box in
            datePickerSheet(for: box.index)
        }
    }

    @ViewBuilder
    private func fieldView(_ field: BotContent.Form.Field) -> some View {
        let value = formState.values[field.index] ?? ""
        let label = fieldLabel(field)

        switch field.type {
        case .select:
            VStack(alignment: .leading, spacing: 6) {
                Text(label).font(textFont(size: 13)).foregroundColor(colors.textSecondary)
                ForEach(field.options, id: \.self) { option in
                    QuickReplyButton(text: option, enabled: fieldsEnabled, selected: value == option, onTap: { onFieldChange(field.index, option) })
                }
            }
        case .date:
            VStack(alignment: .leading, spacing: 6) {
                Text(label).font(textFont(size: 13)).foregroundColor(colors.textSecondary)
                Button(action: { showDatePickerForField = field.index }) {
                    Text(value.isEmpty ? (field.placeholder ?? "Select a date") : value)
                        .font(textFont(size: 14))
                        .foregroundColor(colors.accent)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 10)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(colors.accent, lineWidth: 1))
                }
                .disabled(!fieldsEnabled)
            }
        case .media:
            let uploading = formState.uploadingFields.contains(field.index)
            let fileName = formState.fileNames[field.index]
            VStack(alignment: .leading, spacing: 6) {
                Text(label).font(textFont(size: 13)).foregroundColor(colors.textSecondary)
                Button(action: { onPickMediaField(field.index) }) {
                    Text(uploading ? "Uploading…" : (fileName?.isEmpty == false ? fileName! : "Choose file"))
                        .font(textFont(size: 14))
                        .foregroundColor(colors.accent)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 10)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(colors.accent, lineWidth: 1))
                }
                .disabled(!fieldsEnabled || uploading)
            }
        case .other:
            Text("\(label) (unsupported field type)").font(textFont(size: 13)).foregroundColor(colors.textDisabled)
        case .text, .number, .email, .phone:
            VStack(alignment: .leading, spacing: 4) {
                Text(label).font(textFont(size: 13)).foregroundColor(colors.textSecondary)
                TextField(field.placeholder ?? "", text: Binding(get: { value }, set: { onFieldChange(field.index, $0) }))
                    .keyboardType(keyboardType(for: field.type))
                    .disabled(!fieldsEnabled)
                    .padding(10)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(fieldError(field) != nil ? formErrorColorForm : colors.inputBorder, lineWidth: 1))
            }
        }
    }

    private func datePickerSheet(for fieldIndex: Int) -> some View {
        let field = content.fields.first { $0.index == fieldIndex }
        let dateRules = field?.validation?.dateRules
        return VStack {
            DatePicker("", selection: $pickedDate, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .padding()
            HStack {
                Button("Cancel") { showDatePickerForField = nil }
                Spacer()
                Button("OK") {
                    let selected = SimpleDate(date: pickedDate)
                    if dateRules == nil || !DateAvailability.isDisabled(dateRules!, selected) {
                        onFieldChange(fieldIndex, DateAvailability.format(selected, pattern: dateRules?.dateFormat ?? "DD MMM YYYY"))
                        showDatePickerForField = nil
                    }
                }
            }
            .padding()
        }
    }

    private func fieldLabel(_ field: BotContent.Form.Field) -> String {
        var label = field.label ?? field.placeholder ?? "Field \(field.index + 1)"
        if field.isRequired { label += " *" }
        return label
    }

    private func fieldError(_ field: BotContent.Form.Field) -> String? {
        guard formState.attemptedSubmit else { return nil }
        return FormFieldValidator.validate(field, value: formState.values[field.index] ?? "")
    }

    private func keyboardType(for type: BotContent.Form.FieldType) -> UIKeyboardType {
        switch type {
        case .email: return .emailAddress
        case .phone: return .phonePad
        case .number: return .numberPad
        default: return .default
        }
    }

    private func textFont(size: CGFloat) -> Font {
        if let name = typography.textFontName { return .custom(name, size: size) }
        return .system(size: size)
    }
}

private struct FieldIndexBox: Identifiable {
    var index: Int
    var id: Int { index }
}
