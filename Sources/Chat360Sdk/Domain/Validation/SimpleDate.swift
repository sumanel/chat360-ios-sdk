import Foundation

/// A pure calendar date (year/month/day, no time-of-day or timezone) - the Swift analog of
/// `java.time.LocalDate`, which `DateAvailability` is built around. Using `Foundation.Date`
/// directly here would reintroduce timezone ambiguity that `LocalDate` deliberately has none of.
struct SimpleDate: Equatable, Comparable, Hashable {
    var year: Int
    var month: Int
    var day: Int

    static func < (lhs: SimpleDate, rhs: SimpleDate) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    static func today(calendar: Calendar = SimpleDate.utcCalendar) -> SimpleDate {
        let comps = calendar.dateComponents([.year, .month, .day], from: Date())
        return SimpleDate(year: comps.year ?? 1970, month: comps.month ?? 1, day: comps.day ?? 1)
    }

    /// 0 = Sunday .. 6 = Saturday, matching dayjs's `.day()`.
    var weekdayIndex: Int? {
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        guard let date = SimpleDate.utcCalendar.date(from: comps) else { return nil }
        return SimpleDate.utcCalendar.component(.weekday, from: date) - 1
    }

    static var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        return calendar
    }
}

extension SimpleDate {
    /// Bridges to/from SwiftUI's `DatePicker`, which works in `Foundation.Date`/local time zone -
    /// conversions always go through the UTC calendar so the y/m/d triple round-trips exactly.
    init(date: Date, calendar: Calendar = SimpleDate.utcCalendar) {
        let comps = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: comps.year ?? 1970, month: comps.month ?? 1, day: comps.day ?? 1)
    }

    var foundationDate: Date {
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        return SimpleDate.utcCalendar.date(from: comps) ?? Date()
    }
}
