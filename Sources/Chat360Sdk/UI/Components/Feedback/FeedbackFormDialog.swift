import SwiftUI

private let defaultFeedbackRating = 5

/// Field types rendered directly; checkbox-matrix/radio-matrix/rank/file fall back to a plain
/// notice rather than being silently dropped.
private let supportedFeedbackFieldTypes: Set<String> = ["label", "textarea", "textbox", "dropdown", "radio", "checkbox", "date"]

/// The post-chat configurable survey: a rating (star/emoji) picks which
/// `FeedbackConfig.trigger_rules` form applies, then that form's fields render below it.
/// `onSubmit` receives the rating and every field's value already concatenated into one text blob
/// (mirrors `buildFeedbackText()`) - the session path never sends a separate structured per-field map.
struct FeedbackFormDialog: View {
    var feedbackConfig: FeedbackConfig
    var onSubmit: (_ rating: Int?, _ feedbackText: String) -> Void
    var onDismiss: () -> Void

    @Environment(\.chat360Colors) private var colors
    @Environment(\.chat360Typography) private var typography

    private var showDefaultForm: Bool { feedbackConfig.show_default_form }
    private var defaultRating: Int { (feedbackConfig.rating?.scale).flatMap { $0 > 0 ? $0 : nil } ?? defaultFeedbackRating }

    // Asymmetric initial state: showing the default form starts with no rating picked yet; relying
    // on trigger_rules instead starts with the top rating pre-selected.
    @State private var rating: Int?
    @State private var attemptedSubmit = false
    @State private var values: [String: String] = [:]
    @State private var checkboxValues: [String: [String]] = [:]

    init(feedbackConfig: FeedbackConfig, onSubmit: @escaping (_ rating: Int?, _ feedbackText: String) -> Void, onDismiss: @escaping () -> Void) {
        self.feedbackConfig = feedbackConfig
        self.onSubmit = onSubmit
        self.onDismiss = onDismiss
        let showDefault = feedbackConfig.show_default_form
        let defaultScale = (feedbackConfig.rating?.scale).flatMap { $0 > 0 ? $0 : nil } ?? defaultFeedbackRating
        _rating = State(initialValue: showDefault ? nil : defaultScale)
    }

    private var activeFormId: String? {
        if showDefaultForm { return "default" }
        if feedbackConfig.trigger_rules.isEmpty { return nil }
        return resolveFeedbackFormId(rating: rating ?? defaultFeedbackRating, rules: feedbackConfig.trigger_rules)
    }

    private var activeForm: FeedbackConfig.FeedbackFormDefinition? {
        activeFormId.flatMap { feedbackConfig.activeForm($0) }
    }

    private var isNoneForm: Bool { activeFormId == "none" }

    private var displayTitle: String? {
        let widgetTitle = activeForm?.widgetTitle?.trimmingCharacters(in: .whitespaces)
        if let widgetTitle, !widgetTitle.isEmpty { return widgetTitle }
        let title = activeForm?.title?.trimmingCharacters(in: .whitespaces)
        if let title, !title.isEmpty { return title }
        return nil
    }

    private var showFormContent: Bool {
        guard let activeForm else { return false }
        return showDefaultForm || (!isNoneForm && (displayTitle != nil || !activeForm.fields.isEmpty))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("How was your experience?")
                .font(textFont(size: 16))
                .foregroundColor(colors.textPrimary)
            Spacer().frame(height: 14)
            RatingRow(style: feedbackConfig.rating?.style ?? "star", scale: defaultRating, selected: rating, onSelect: { rating = $0 })
            Spacer().frame(height: 16)

            if showFormContent, let activeForm {
                if let displayTitle {
                    Text(displayTitle).font(textFont(size: 14)).foregroundColor(colors.textPrimary).padding(.bottom, 8)
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
                guard !hasValidationErrors() else { return }
                onSubmit(rating, buildFeedbackText())
            }) {
                Text("Submit")
                    .font(textFont(size: 15))
                    .fontWeight(.medium)
                    .foregroundColor(colors.accentContrast)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(colors.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(20)
        .background(colors.backgroundElevated)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .padding(.horizontal, 16)
        .frame(maxHeight: 560)
    }

    private func isMissingRequired(fieldId: String, type: String, required: Bool) -> Bool {
        guard required else { return false }
        if type == "checkbox" { return (checkboxValues[fieldId] ?? []).isEmpty }
        return (values[fieldId] ?? "").trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func buildFeedbackText() -> String {
        let fields = activeForm?.fields ?? []
        let parts = fields.compactMap { field -> String? in
            let type = normalizeFeedbackFieldType(field.type)
            switch type {
            case "label":
                return nil
            case "checkbox":
                let selected = checkboxValues[field.id] ?? []
                return selected.isEmpty ? nil : selected.joined(separator: ", ")
            default:
                let value = values[field.id] ?? ""
                return value.trimmingCharacters(in: .whitespaces).isEmpty ? nil : value
            }
        }
        return parts.filter { !$0.isEmpty }.joined(separator: "\n")
    }

    private func hasValidationErrors() -> Bool {
        let fields = activeForm?.fields ?? []
        return fields.contains { field in
            let type = normalizeFeedbackFieldType(field.type)
            return supportedFeedbackFieldTypes.contains(type) && isMissingRequired(fieldId: field.id, type: type, required: field.required)
        }
    }

    private func textFont(size: CGFloat) -> Font {
        if let name = typography.textFontName { return .custom(name, size: size) }
        return .system(size: size)
    }
}

private struct RatingRow: View {
    var style: String
    var scale: Int
    var selected: Int?
    var onSelect: (Int) -> Void

    @Environment(\.chat360Colors) private var colors

    var body: some View {
        HStack(spacing: style == "star" ? 4 : 6) {
            if style == "star" {
                ForEach(0..<scale, id: \.self) { index in
                    let filled = selected != nil && index < selected!
                    Button(action: { onSelect(index + 1) }) {
                        Image(systemName: filled ? "star.fill" : "star")
                            .foregroundColor(filled ? colors.accent : colors.line)
                            .font(.system(size: 24))
                    }
                    .buttonStyle(.plain)
                }
            } else {
                let emojiSet = ["😞", "😕", "😐", "😊", "🤩"]
                ForEach(Array(emojiSet.enumerated()), id: \.offset) { index, emoji in
                    let isSelected = selected == index + 1
                    Button(action: { onSelect(index + 1) }) {
                        Text(emoji).font(.system(size: isSelected ? 28 : 24))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct FeedbackFieldRow: View {
    var field: FeedbackConfig.FeedbackField
    var value: String
    var checkboxValue: [String]
    var showError: Bool
    var onValueChange: (String) -> Void
    var onCheckboxChange: ([String]) -> Void

    @Environment(\.chat360Colors) private var colors
    @Environment(\.chat360Typography) private var typography

    private var type: String { normalizeFeedbackFieldType(field.type) }
    private var hasError: Bool {
        guard showError, field.required else { return false }
        return type == "checkbox" ? checkboxValue.isEmpty : value.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        if type == "label" {
            Text(field.label ?? "").font(textFont(size: 13)).foregroundColor(colors.textSecondary)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                if let label = field.label {
                    Text(label + (field.required ? " *" : "")).font(textFont(size: 13)).foregroundColor(colors.textPrimary)
                }
                fieldInput
                if hasError {
                    Text("This field is required").font(textFont(size: 12)).foregroundColor(activeRed)
                }
            }
        }
    }

    @ViewBuilder
    private var fieldInput: some View {
        switch type {
        case "textarea", "textbox":
            TextField("", text: Binding(get: { value }, set: onValueChange))
                .font(textFont(size: 14))
                .padding(12)
                .background(colors.inputBackground)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        case "date":
            TextField(field.placeholder ?? "DD-MM-YYYY", text: Binding(get: { value }, set: onValueChange))
                .font(textFont(size: 14))
                .padding(12)
                .background(colors.inputBackground)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        // Single-select list where the label doubles as the option's value; exactly one can be picked.
        case "dropdown":
            let options = normalizeFeedbackOptions(field.options)
            VStack(alignment: .leading, spacing: 4) {
                ForEach(options, id: \.value) { option in
                    radioRow(label: option.label, selected: value == option.label) { onValueChange(option.label) }
                }
            }
        case "radio":
            let options = normalizeFeedbackOptions(field.options)
            VStack(alignment: .leading, spacing: 4) {
                ForEach(options, id: \.value) { option in
                    radioRow(label: option.label, selected: value == option.value) { onValueChange(option.value) }
                }
            }
        case "checkbox":
            let options = normalizeFeedbackOptions(field.options)
            VStack(alignment: .leading, spacing: 4) {
                ForEach(options, id: \.value) { option in
                    let checked = checkboxValue.contains(option.value)
                    Button(action: {
                        onCheckboxChange(checked ? checkboxValue.filter { $0 != option.value } : checkboxValue + [option.value])
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: checked ? "checkmark.square.fill" : "square")
                                .foregroundColor(checked ? colors.accent : colors.textSecondary)
                            Text(option.label).font(textFont(size: 14)).foregroundColor(colors.textPrimary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        default:
            // checkbox-matrix/radio-matrix/rank/file aren't supported yet - an honest placeholder
            // beats silently dropping the field.
            Text("This field type (\(type)) isn't supported in the app yet.")
                .font(textFont(size: 12))
                .foregroundColor(colors.textSecondary)
        }
    }

    private func radioRow(label: String, selected: Bool, onTap: @escaping () -> Void) -> some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .foregroundColor(selected ? colors.accent : colors.textSecondary)
                Text(label).font(textFont(size: 14)).foregroundColor(colors.textPrimary)
            }
        }
        .buttonStyle(.plain)
    }

    private func textFont(size: CGFloat) -> Font {
        if let name = typography.textFontName { return .custom(name, size: size) }
        return .system(size: size)
    }
}
