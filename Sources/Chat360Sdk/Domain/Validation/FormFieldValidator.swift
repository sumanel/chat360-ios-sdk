import Foundation

/// Per-field-type checks first (each with its own message), then the generic required check,
/// then a single OR-chain whose failures all share one generic message. The order is
/// deliberate, including the quirk that the EMAIL/TEXT "Test"-word and alpha-only checks run
/// *before* the required check, so they can fire on values that also happen to be blank.
enum FormFieldValidator {

    private static let blockedPhoneNumbers: Set<String> = {
        var set = Set((0...9).map { String(repeating: String($0), count: 10) })
        set.formUnion(["1122334455", "1231231231", "2345678901", "3456789012", "4567890123", "5678901234", "0101010101"])
        return set
    }()

    /// Returns an error message, or nil if `value` passes every rule for this field.
    static func validate(_ field: BotContent.Form.Field, value: String) -> String? {
        let v = field.validation ?? BotContent.Form.FieldValidation()

        // MEDIA fields skip every format/length check in this matrix (they don't apply to a
        // file), but a required upload still can't be left blank; `value` here is the uploaded
        // URL, set once the picker finishes.
        if field.type == .media {
            return (v.isRequired && value.isEmpty) ? (v.errorMessage ?? "This field is required") : nil
        }

        if field.type == .email && InputValidators.validateTest(value) {
            return "Email cannot contain the word 'Test'"
        }
        if field.type == .phone && blockedPhoneNumbers.contains(value) {
            return "This phone number is blocked"
        }
        if field.type == .text && InputValidators.validateTestName(value.lowercased()) {
            return "Name cannot contain the word 'Test'"
        }
        if field.type == .text && v.userInputType == "alpha" && !InputValidators.hasOnlyCharacter(value) {
            return "Only characters and space are allowed'"
        }

        if v.isRequired && value.isEmpty { return v.errorMessage ?? "This field is required" }
        if !v.isRequired && value.isEmpty { return nil }

        let numeric = Double(value)
        let dateRules = v.dateRules
        let parsedDate: SimpleDate? = (field.type == .date && dateRules != nil)
            ? DateAvailability.parse(value, pattern: dateRules!.dateFormat)
            : nil

        // JS's `+value > maxCount` is false when value isn't numeric (NaN comparisons are always
        // false) - a non-numeric value does NOT fail these two checks on its own.
        let invalid = (v.maxCharacters.map { value.count > $0 } ?? false)
            || (v.minCharacters.map { value.count < $0 } ?? false)
            || (v.email && !InputValidators.validateEmail(value))
            || (v.maxCount != nil && numeric != nil && numeric! > v.maxCount!)
            || (v.minCount != nil && numeric != nil && numeric! < v.minCount!)
            || (v.phone && !InputValidators.validatePhoneNumber(value, international: v.allowInternationalNumber))
            || (parsedDate != nil && dateRules != nil && dateRules!.isScheduledDate && DateAvailability.isDisabled(dateRules!, parsedDate!))
            || (field.type == .number && numeric == nil)
            || (v.numberFormat == "DECIMAL" && !value.contains("."))
            || (v.numberFormat == "NUMBER" && value.contains("."))

        return invalid ? (v.errorMessage ?? "Invalid input") : nil
    }
}
