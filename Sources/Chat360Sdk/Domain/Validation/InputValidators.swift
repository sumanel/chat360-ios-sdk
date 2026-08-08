import Foundation

/// The server-side contract for what counts as a valid email/phone/name is fixed independently
/// of the client, so these regexes/checks must match it exactly.
enum InputValidators {
    private static let emailPattern =
        #"^(([^<>()\[\]\\.,;:\s@"]+(\.[^<>()\[\]\\.,;:\s@"]+)*)|(".+"))@"# +
        #"((\[[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\])|(([a-zA-Z\-0-9]+\.)+[a-zA-Z]{2,}))$"#
    private static let testEmailPattern = #"^(test@)|(@test\..*)"#
    private static let testNamePattern = #"(^|\s)test(\s|$)"#
    private static let phonePattern = #"^\+?([0-9]{2})\)?[-. ]?([0-9]{4})[-. ]?([0-9]{4})$"#
    private static let phonePatternInternational = #"^\+?([0-9]{2})\)?[- ]?([0-9]{4})[- ]?([0-9]{4})[- ]?([0-9]{0,3})$"#
    private static let alphaOnlyPattern = #"^[a-zA-Z\s]+$"#

    static func validateEmail(_ email: String) -> Bool {
        matchesFully(email.lowercased(), pattern: emailPattern)
    }

    /// Blocks the literal word "test" as an email local-part/domain - a deliberate guard, not a real format rule.
    static func validateTest(_ value: String) -> Bool {
        containsMatch(value.lowercased(), pattern: testEmailPattern, caseInsensitive: true)
    }

    /// Blocks the standalone word "test" anywhere in a name field.
    static func validateTestName(_ value: String) -> Bool {
        containsMatch(value.lowercased(), pattern: testNamePattern, caseInsensitive: true)
    }

    /// Rejects phone numbers made of a single repeated digit (e.g. "1111111111") before format-checking.
    static func validatePhoneNumber(_ phone: String, international: Bool) -> Bool {
        let containsSameCharacters = !phone.isEmpty && phone.allSatisfy { $0 == phone.first }
        if containsSameCharacters { return false }
        let pattern = international ? phonePatternInternational : phonePattern
        return matchesFully(phone.lowercased(), pattern: pattern)
    }

    static func hasOnlyCharacter(_ value: String) -> Bool {
        matchesFully(value, pattern: alphaOnlyPattern)
    }

    /// HTML-entity-escapes a value before it goes out over the wire.
    static func sanitizeInput(_ input: String) -> String {
        input
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "/", with: "&#x2F;")
    }

    private static func matchesFully(_ text: String, pattern: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range) else { return false }
        return match.range == range
    }

    private static func containsMatch(_ text: String, pattern: String, caseInsensitive: Bool = false) -> Bool {
        let options: NSRegularExpression.Options = caseInsensitive ? [.caseInsensitive] : []
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return false }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.firstMatch(in: text, range: range) != nil
    }
}
