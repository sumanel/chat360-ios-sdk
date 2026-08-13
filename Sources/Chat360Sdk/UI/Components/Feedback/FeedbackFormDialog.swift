import SwiftUI

@available(iOS 15.0, *)
private let defaultRating = 5

@available(iOS 15.0, *)
private let supportedFeedbackFieldTypes: Set<String> = ["label", "textarea", "textbox", "dropdown", "radio", "checkbox", "date"]

@available(iOS 15.0, *)
public struct FeedbackFormDialog: View {
    @Environment(\.chat360Colors) private var colors
    @Environment(\.chat360Typography) private var typography

    private let feedbackConfig: FeedbackConfig
    private let onSubmit: (Int?, String) -> Void
    private let onDismiss: () -> Void

    @State private var rating: Int?
    @State private var attemptedSubmit = false
    @State private var values: [String: String] = [:]
    @State private var checkboxValues: [String: [String]] = [:]

    public init(feedbackConfig: FeedbackConfig, onSubmit: @escaping (Int?, String) -> Void, onDismiss: @escaping () -> Void) {
        self.feedbackConfig = feedbackConfig
        self.onSubmit = onSubmit
        self.onDismiss = onDismiss
        let showDefaultForm = feedbackConfig.show_default_form
        let scale = feedbackConfig.rating?.scale ?? 0
        let initialRating = showDefaultForm ? nil : (scale > 0 ? scale : defaultRating)
        self._rating = State(initialValue: initialRating)
    }

    private var effectiveScale: Int {
        let scale = feedbackConfig.rating?.scale ?? 0
        return scale > 0 ? scale : defaultRating
    }

    private var activeFormId: String? {
        if feedbackConfig.show_default_form { return "default" }
        if feedbackConfig.trigger_rules.isEmpty { return nil }
        return resolveFeedbackFormId(rating: rating ?? defaultRating, rules: feedbackConfig.trigger_rules)
    }

    private var activeForm: FeedbackConfig.FeedbackFormDefinition? {
        activeFormId.flatMap { feedbackConfig.activeForm($0) }
    }

    private var isNoneForm: Bool { activeFormId == "none" }

    private var displayTitle: String? {
        let widgetTitle = activeForm?.widgetTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let widgetTitle, !widgetTitle.isEmpty { return widgetTitle }
        let title = activeForm?.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let title, !title.isEmpty { return title }
        return nil
    }

    private var showFormContent: Bool {
        guard let activeForm else { return false }
        return feedbackConfig.show_default_form || (!isNoneForm && (displayTitle != nil || !activeForm.fields.isEmpty))
    }

    private func isMissingRequired(fieldId: String, type: String, required: Bool) -> Bool {
        guard required else { return false }
        if type == "checkbox" { return (checkboxValues[fieldId] ?? []).isEmpty }
        return (values[fieldId] ?? "").isBlank
    }

    private func buildFeedbackText() -> String {
        let fields = activeForm?.fields ?? []
        let parts = fields.compactMap { field -> String? in
            let type = normalizeFeedbackFieldType(field.type)
            switch type {
            case "label": return nil
            case "checkbox":
                let checked = checkboxValues[field.id] ?? []
                return checked.isEmpty ? nil : checked.joined(separator: ", ")
            default:
                let value = values[field.id] ?? ""
                return value.isBlank ? nil : value
            }
        }
        return parts.joined(separator: "\n")
    }

    private func hasValidationErrors() -> Bool {
        let fields = activeForm?.fields ?? []
        return fields.contains { field in
            let type = normalizeFeedbackFieldType(field.type)
            return supportedFeedbackFieldTypes.contains(type) && isMissingRequired(fieldId: field.id, type: type, required: field.required)
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("How was your experience?")
                .font(typography.textFamily.font(size: 16))
                .foregroundColor(colors.textPrimary)
            Spacer().frame(height: 14)
            RatingRow(style: feedbackConfig.rating?.style ?? "star", scale: effectiveScale, selected: rating) { rating = $0 }
            Spacer().frame(height: 16)

            if showFormContent, let activeForm {
                if let displayTitle {
                    Text(displayTitle)
                        .font(typography.textFamily.font(size: 14))
                        .foregroundColor(colors.textPrimary)
                        .padding(.bottom, 8)
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(activeForm.fields, id: \.id) { field in
                            FeedbackFieldRow(
                                field: field,
                                value: values[field.id] ?? "",
                                checkboxValue: checkboxValues[field.id] ?? [],
                                showError: attemptedSubmit,
                                onValueChange: { values[field.id] = $0 },
                                onCheckboxChange: { checkboxValues[field.id] = $0 }
                            )
                        }
                    }
                }
                Spacer().frame(height: 16)
            }

            Button(action: {
                attemptedSubmit = true
                if hasValidationErrors() { return }
                onSubmit(rating, buildFeedbackText())
            }) {
                Text("Submit")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .foregroundColor(colors.accentContrast)
                    .background(colors.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(20)
        .frame(maxHeight: 560)
        .background(colors.backgroundElevated)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .padding(.horizontal, 16)
    }
}

@available(iOS 15.0, *)
private struct RatingRow: View {
    @Environment(\.chat360Colors) private var colors
    let style: String
    let scale: Int
    let selected: Int?
    let onSelect: (Int) -> Void

    var body: some View {
        HStack(spacing: 0) {
            if style == "star" {
                ForEach(0..<scale, id: \.self) { index in
                    let filled = selected.map { index < $0 } ?? false
                    Chat360Icon.star.image
                        .foregroundColor(filled ? colors.accent : colors.line)
                        .font(.system(size: 28))
                        .padding(.trailing, 4)
                        .onTapGesture { onSelect(index + 1) }
                }
            } else {
                ForEach(Array(["😞", "😕", "😐", "😊", "🤩"].enumerated()), id: \.offset) { index, emoji in
                    let isSelected = selected == index + 1
                    Text(emoji)
                        .font(.system(size: isSelected ? 28 : 24))
                        .padding(.trailing, 6)
                        .onTapGesture { onSelect(index + 1) }
                }
            }
        }
    }
}

@available(iOS 15.0, *)
private struct FeedbackFieldRow: View {
    @Environment(\.chat360Colors) private var colors
    @Environment(\.chat360Typography) private var typography

    let field: FeedbackConfig.FeedbackField
    let value: String
    let checkboxValue: [String]
    let showError: Bool
    let onValueChange: (String) -> Void
    let onCheckboxChange: ([String]) -> Void

    private var type: String { normalizeFeedbackFieldType(field.type) }
    private var hasError: Bool {
        guard showError, field.required else { return false }
        return type == "checkbox" ? checkboxValue.isEmpty : value.isBlank
    }

    var body: some View {
        if type == "label" {
            Text(field.label ?? "")
                .font(typography.textFamily.font(size: 13))
                .foregroundColor(colors.textSecondary)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                if let label = field.label {
                    Text(label + (field.required ? " *" : ""))
                        .font(typography.textFamily.font(size: 13))
                        .foregroundColor(colors.textPrimary)
                        .padding(.bottom, 4)
                }
                fieldBody
                if hasError {
                    Text("This field is required")
                        .font(typography.textFamily.font(size: 12))
                        .foregroundColor(activeRed)
                        .padding(.top, 2)
                }
            }
        }
    }

    @ViewBuilder
    private var fieldBody: some View {
        switch type {
        case "textarea", "textbox":
            TextField("", text: Binding(get: { value }, set: onValueChange))
                .font(typography.textFamily.font(size: 14))
                .foregroundColor(colors.textPrimary)
                .padding(12)
                .background(colors.inputBackground)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        case "date":
            TextField(field.placeholder ?? "DD-MM-YYYY", text: Binding(get: { value }, set: onValueChange))
                .font(typography.textFamily.font(size: 14))
                .foregroundColor(colors.textPrimary)
                .padding(12)
                .background(colors.inputBackground)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        case "dropdown":
            let options = normalizeFeedbackOptions(field.options)
            VStack(alignment: .leading, spacing: 4) {
                ForEach(options, id: \.value) { option in
                    HStack {
                        Image(systemName: value == option.label ? "largecircle.fill.circle" : "circle")
                            .foregroundColor(colors.accent)
                        Text(option.label).font(typography.textFamily.font(size: 14)).foregroundColor(colors.textPrimary)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { onValueChange(option.label) }
                }
            }
        case "radio":
            let options = normalizeFeedbackOptions(field.options)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(options, id: \.value) { option in
                    HStack {
                        Image(systemName: value == option.value ? "largecircle.fill.circle" : "circle")
                            .foregroundColor(colors.accent)
                        Text(option.label).font(typography.textFamily.font(size: 14)).foregroundColor(colors.textPrimary)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { onValueChange(option.value) }
                }
            }
        case "checkbox":
            let options = normalizeFeedbackOptions(field.options)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(options, id: \.value) { option in
                    let checked = checkboxValue.contains(option.value)
                    HStack {
                        ZStack {
                            RoundedRectangle(cornerRadius: 4).fill(checked ? colors.accent : colors.inputBackground).frame(width: 20, height: 20)
                            if checked { Chat360Icon.check.image.foregroundColor(colors.accentContrast).font(.system(size: 12)) }
                        }
                        Text(option.label).font(typography.textFamily.font(size: 14)).foregroundColor(colors.textPrimary)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        onCheckboxChange(checked ? checkboxValue.filter { $0 != option.value } : checkboxValue + [option.value])
                    }
                }
            }
        default:
            Text("This field type (\(type)) isn't supported in the app yet.")
                .font(typography.textFamily.font(size: 12))
                .foregroundColor(colors.textSecondary)
        }
    }
}
