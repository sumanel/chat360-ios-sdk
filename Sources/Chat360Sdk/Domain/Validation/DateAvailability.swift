import Foundation

public enum DateAvailability {
    public static func isDisabled(_ rules: DateRules, date: SimpleDate) -> Bool {
        let today = SimpleDate.today()
        if rules.disableFuture && date > today { return true }
        if rules.disableCurrent && date == today { return true }
        if rules.disablePrevious && date < today { return true }
        if rules.isScheduledDate {
            let dayIndex = date.weekdayIndex
            if let disabledDays = rules.disabledDays, dayIndex < disabledDays.count, disabledDays[dayIndex] { return true }
            if (rules.disabledDates ?? []).contains(where: { sameDay($0, date) }) { return true }
        }
        if rules.manageWithVariable, let variableDates = rules.variableDates, !variableDates.isEmpty {
            let inVariable = variableDates.contains { sameDay($0, date) }
            switch rules.variableMode {
            case "disable_in_var": return inVariable
            case "disable_not_in_var": return !inVariable
            default: return false
            }
        }
        return false
    }

    public static func parse(_ value: String, pattern: String) -> SimpleDate? {
        let formatter = DateFormatter()
        formatter.dateFormat = toSwiftPattern(pattern)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let date = formatter.date(from: trimmed) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return SimpleDate(year: components.year!, month: components.month!, day: components.day!)
    }

    public static func format(_ date: SimpleDate, pattern: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = toSwiftPattern(pattern)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        var components = DateComponents()
        components.year = date.year
        components.month = date.month
        components.day = date.day
        let resolved = calendar.date(from: components)!
        return formatter.string(from: resolved)
    }

    private static func toSwiftPattern(_ pattern: String) -> String {
        pattern
            .replacingOccurrences(of: "YYYY", with: "yyyy")
            .replacingOccurrences(of: "YY", with: "yy")
            .replacingOccurrences(of: "DD", with: "dd")
            .replacingOccurrences(of: "D", with: "d")
    }

    private static func sameDay(_ raw: String, _ date: SimpleDate) -> Bool {
        guard let parsed = SimpleDate.parseIso(raw) else { return false }
        return parsed == date
    }
}
