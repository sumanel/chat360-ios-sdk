import SwiftUI
import UniformTypeIdentifiers

@available(iOS 15.0, *)
public struct FormContent: View {
    @Environment(\.chat360Colors) private var colors
    @Environment(\.chat360Typography) private var typography

    private let message: ChatMessage
    private let content: BotContent.Form
    private let isLiveChat: Bool
    private let onFieldChange: (Int, String) -> Void
    private let onMediaFieldPicked: (Int, Data, String, String) -> Void
    private let onSubmit: () -> Void

    public init(
        message: ChatMessage, content: BotContent.Form, isLiveChat: Bool,
        onFieldChange: @escaping (Int, String) -> Void,
        onMediaFieldPicked: @escaping (Int, Data, String, String) -> Void,
        onSubmit: @escaping () -> Void
    ) {
        self.message = message
        self.content = content
        self.isLiveChat = isLiveChat
        self.onFieldChange = onFieldChange
        self.onMediaFieldPicked = onMediaFieldPicked
        self.onSubmit = onSubmit
    }

    private var formState: FormState { message.formState ?? FormState() }
    private var submitted: Bool { formState.submitted }
    private var fieldsEnabled: Bool { !submitted && !isLiveChat }
    private var canSubmit: Bool { fieldsEnabled && formState.uploadingFields.isEmpty }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(content.fields, id: \.index) { field in
                FormFieldView(
                    field: field,
                    value: formState.values[field.index] ?? "",
                    error: formState.attemptedSubmit ? FormFieldValidator.validate(field, value: formState.values[field.index] ?? "") : nil,
                    fieldsEnabled: fieldsEnabled,
                    uploading: formState.uploadingFields.contains(field.index),
                    fileName: formState.fileNames[field.index],
                    onFieldChange: onFieldChange,
                    onMediaFieldPicked: onMediaFieldPicked
                )
                Spacer().frame(height: 10)
            }
            Button(action: onSubmit) {
                Text(submitted ? "Submitted" : content.submitButtonText)
                    .font(typography.textFamily.font(size: 15, weight: .medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .foregroundColor(colors.accentContrast)
                    .background(canSubmit ? colors.accent : colors.textDisabled)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .disabled(!canSubmit)
        }
    }
}

@available(iOS 15.0, *)
private struct FormFieldView: View {
    @Environment(\.chat360Colors) private var colors
    @Environment(\.chat360Typography) private var typography

    let field: BotContent.Form.Field
    let value: String
    let error: String?
    let fieldsEnabled: Bool
    let uploading: Bool
    let fileName: String?
    let onFieldChange: (Int, String) -> Void
    let onMediaFieldPicked: (Int, Data, String, String) -> Void

    @State private var showDatePicker = false
    @State private var pickedDate = Date()
    @State private var showFilePicker = false

    private var label: String {
        var text = field.label ?? field.placeholder ?? "Field \(field.index + 1)"
        if field.isRequired { text += " *" }
        return text
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch field.type {
            case .select:
                fieldLabel
                Spacer().frame(height: 6)
                ForEach(field.options, id: \.self) { option in
                    QuickReplyButton(text: option, enabled: fieldsEnabled, selected: value == option) {
                        onFieldChange(field.index, option)
                    }
                    Spacer().frame(height: 6)
                }
            case .date:
                fieldLabel
                Spacer().frame(height: 6)
                Button(action: { showDatePicker = true }) {
                    Text(value.isBlank ? (field.placeholder ?? "Select a date") : value)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .foregroundColor(colors.accent)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(colors.accent, lineWidth: 1))
                }
                .disabled(!fieldsEnabled)
                .sheet(isPresented: $showDatePicker) {
                    VStack {
                        DatePicker("", selection: $pickedDate, displayedComponents: .date)
                            .datePickerStyle(.graphical)
                            .labelsHidden()
                        HStack {
                            Button("Cancel") { showDatePicker = false }
                            Spacer()
                            Button("OK") {
                                var calendar = Calendar(identifier: .gregorian)
                                calendar.timeZone = TimeZone(identifier: "UTC")!
                                let components = calendar.dateComponents([.year, .month, .day], from: pickedDate)
                                let simpleDate = SimpleDate(year: components.year!, month: components.month!, day: components.day!)
                                let format = field.validation?.dateRules?.dateFormat ?? "DD MMM YYYY"
                                onFieldChange(field.index, DateAvailability.format(simpleDate, pattern: format))
                                showDatePicker = false
                            }
                        }.padding()
                    }.padding()
                }
            case .media:
                fieldLabel
                Spacer().frame(height: 6)
                Button(action: { showFilePicker = true }) {
                    Text(uploading ? "Uploading…" : (!(fileName?.isBlank ?? true) ? fileName! : "Choose file"))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .foregroundColor(colors.accent)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(colors.accent, lineWidth: 1))
                }
                .disabled(!fieldsEnabled || uploading)
                .fileImporter(isPresented: $showFilePicker, allowedContentTypes: [.data], allowsMultipleSelection: false) { result in
                    guard let url = try? result.get().first, let payload = readAttachment(url: url) else { return }
                    onMediaFieldPicked(field.index, payload.bytes, payload.fileName, payload.mimeType)
                }
            case .other:
                Text("\(label) (unsupported field type)")
                    .font(typography.textFamily.font(size: 13))
                    .foregroundColor(colors.textDisabled)
            default:
                TextField(field.placeholder ?? "", text: Binding(get: { value }, set: { onFieldChange(field.index, $0) }))
                    .font(typography.textFamily.font(size: 15))
                    .foregroundColor(colors.textPrimary)
                    .disabled(!fieldsEnabled)
                    .keyboardType(keyboardType(for: field.type))
                    .padding(12)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(error != nil ? promptErrorColor : colors.inputBorder, lineWidth: 1))
            }
            if let error {
                Spacer().frame(height: 4)
                Text(error).font(typography.textFamily.font(size: 12)).foregroundColor(promptErrorColor)
            }
        }
    }

    private var fieldLabel: some View {
        Text(label)
            .font(typography.textFamily.font(size: 13))
            .foregroundColor(colors.textSecondary)
    }

    private func keyboardType(for type: BotContent.Form.FieldType) -> UIKeyboardType {
        switch type {
        case .email: return .emailAddress
        case .phone: return .phonePad
        case .number: return .numberPad
        default: return .default
        }
    }
}
