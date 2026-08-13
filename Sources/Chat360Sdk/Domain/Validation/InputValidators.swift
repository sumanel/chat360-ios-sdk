import Foundation

public enum InputValidators {
    private static let emailPattern =
        "^(([^<>()\\[\\]\\\\.,;:\\s@\"]+(\\.[^<>()\\[\\]\\\\.,;:\\s@\"]+)*)|(\".+\"))@" +
        "((\\[[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}\\])|(([a-zA-Z\\-0-9]+\\.)+[a-zA-Z]{2,}))$"
    private static let testEmailPattern = "^(test@)|(@test\\..*)"
    private static let testNamePattern = "(^|\\s)test(\\s|$)"
    private static let phonePattern = "^\\+?([0-9]{2})\\)?[-. ]?([0-9]{4})[-. ]?([0-9]{4})$"
    private static let phonePatternInternational = "^\\+?([0-9]{2})\\)?[- ]?([0-9]{4})[- ]?([0-9]{4})[- ]?([0-9]{0,3})$"
    private static let alphaOnlyPattern = "^[a-zA-Z\\s]+$"

    public static func validateEmail(_ email: String) -> Bool {
        matches(emailPattern, email.lowercased())
    }

    public static func validateTest(_ value: String) -> Bool {
        contains(testEmailPattern, value.lowercased(), caseInsensitive: true)
    }

    public static func validateTestName(_ value: String) -> Bool {
        contains(testNamePattern, value.lowercased(), caseInsensitive: true)
    }

    public static func validatePhoneNumber(_ phone: String, international: Bool) -> Bool {
        let containsSameCharacters = !phone.isEmpty && phone.allSatisfy { $0 == phone.first }
        if containsSameCharacters { return false }
        let pattern = international ? phonePatternInternational : phonePattern
        return matches(pattern, phone.lowercased())
    }

    public static func hasOnlyCharacter(_ value: String) -> Bool {
        matches(alphaOnlyPattern, value)
    }

    public static func sanitizeInput(_ input: String) -> String {
        input
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "/", with: "&#x2F;")
    }

    private static func matches(_ pattern: String, _ value: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
        let range = NSRange(location: 0, length: (value as NSString).length)
        guard let match = regex.firstMatch(in: value, range: range) else { return false }
        return match.range == range
    }

    private static func contains(_ pattern: String, _ value: String, caseInsensitive: Bool = false) -> Bool {
        let options: NSRegularExpression.Options = caseInsensitive ? [.caseInsensitive] : []
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return false }
        let range = NSRange(location: 0, length: (value as NSString).length)
        return regex.firstMatch(in: value, range: range) != nil
    }
}
