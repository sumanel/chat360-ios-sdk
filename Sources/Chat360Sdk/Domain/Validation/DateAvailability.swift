import Foundation

/// Ports the disabled-date rule evaluation shared by DATE prompts (standalone) and FORM DATE
/// fields' `excludeDate` - one evaluator so both call sites agree.
enum DateAvailability {

    static func isDisabled(_ rules: DateRules, _ date: SimpleDate) -> Bool {
        let today = SimpleDate.today()
        if rules.disableFuture && date > today { return true }
        if rules.disableCurrent && date == today { return true }
        if rules.disablePrevious && date < today { return true }
        if rules.isScheduledDate {
            let dayIndex = date.weekdayIndex ?? 0
            if let disabledDays = rules.disabledDays, dayIndex >= 0, dayIndex < disabledDays.count, disabledDays[dayIndex] {
                return true
            }
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

    /// Parses a field's typed value against its own dayjs-style `pattern` (e.g. "DD MMM YYYY").
    static func parse(_ value: String, pattern: String) -> SimpleDate? {
        let formatter = dateFormatter(pattern: pattern)
        guard let date = formatter.date(from: value.trimmingCharacters(in: .whitespaces)) else { return nil }
        let comps = SimpleDate.utcCalendar.dateComponents([.year, .month, .day], from: date)
        guard let year = comps.year, let month = comps.month, let day = comps.day else { return nil }
        return SimpleDate(year: year, month: month, day: day)
    }

    /// Formats `date` using the same dayjs-style `pattern` a DATE node's own value round-trips through.
    static func format(_ date: SimpleDate, pattern: String) -> String {
        var comps = DateComponents()
        comps.year = date.year
        comps.month = date.month
        comps.day = date.day
        guard let foundationDate = SimpleDate.utcCalendar.date(from: comps) else { return "" }
        return dateFormatter(pattern: pattern).string(from: foundationDate)
    }

    private static func dateFormatter(pattern: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = toFoundationPattern(pattern)
        return formatter
    }

    private static func toFoundationPattern(_ pattern: String) -> String {
        pattern
            .replacingOccurrences(of: "YYYY", with: "yyyy")
            .replacingOccurrences(of: "YY", with: "yy")
            .replacingOccurrences(of: "DD", with: "dd")
            .replacingOccurrences(of: "D", with: "d")
    }

    private static func sameDay(_ raw: String, _ date: SimpleDate) -> Bool {
        guard let parsed = parseIsoDate(String(raw.prefix(10))) else { return false }
        return parsed == date
    }

    /// Mirrors `LocalDate.parse(raw.take(10))`'s default ISO_LOCAL_DATE parsing.
    private static func parseIsoDate(_ text: String) -> SimpleDate? {
        let parts = text.split(separator: "-")
        guard parts.count == 3, let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
              (1...12).contains(month), (1...31).contains(day) else { return nil }
        return SimpleDate(year: year, month: month, day: day)
    }
}
