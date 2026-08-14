import Foundation

public enum FormFieldValidator {
    private static let blockedPhoneNumbers: Set<String> = {
        var set = Set((0...9).map { String(repeating: String($0), count: 10) })
        set.formUnion(["1122334455", "1231231231", "2345678901", "3456789012", "4567890123", "5678901234", "0101010101"])
        return set
    }()

    public static func validate(_ field: BotContent.Form.Field, value: String) -> String? {
        let v = field.validation ?? BotContent.Form.FieldValidation()

        if field.type == .media {
            if v.isRequired && value.isBlank { return v.errorMessage ?? "This field is required" }
            return nil
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

        if v.isRequired && value.isBlank { return v.errorMessage ?? "This field is required" }
        if !v.isRequired && value.isBlank { return nil }

        let numeric = Double(value)
        let dateRules = v.dateRules
        var parsedDate: SimpleDate? = nil
        if field.type == .date, let dateRules {
            parsedDate = DateAvailability.parse(value, pattern: dateRules.dateFormat)
        }

        let invalid = (v.maxCharacters != nil && value.count > v.maxCharacters!) ||
            (v.minCharacters != nil && value.count < v.minCharacters!) ||
            (v.email && !InputValidators.validateEmail(value)) ||
            (v.maxCount != nil && numeric != nil && numeric! > v.maxCount!) ||
            (v.minCount != nil && numeric != nil && numeric! < v.minCount!) ||
            (v.phone && !InputValidators.validatePhoneNumber(value, international: v.allowInternationalNumber)) ||
            (parsedDate != nil && dateRules != nil && dateRules!.isScheduledDate && DateAvailability.isDisabled(dateRules!, date: parsedDate!)) ||
            (field.type == .number && numeric == nil) ||
            (v.numberFormat == "DECIMAL" && !value.contains(".")) ||
            (v.numberFormat == "NUMBER" && value.contains("."))

        return invalid ? (v.errorMessage ?? "Invalid input") : nil
    }
}
