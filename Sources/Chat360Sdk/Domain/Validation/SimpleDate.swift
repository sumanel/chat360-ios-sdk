import Foundation

public struct SimpleDate: Equatable, Comparable {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    public static func today() -> SimpleDate {
        let components = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: Date())
        return SimpleDate(year: components.year!, month: components.month!, day: components.day!)
    }

    public var weekdayIndex: Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        let date = calendar.date(from: components)!
        return calendar.component(.weekday, from: date) - 1
    }

    public static func < (lhs: SimpleDate, rhs: SimpleDate) -> Bool {
        if lhs.year != rhs.year { return lhs.year < rhs.year }
        if lhs.month != rhs.month { return lhs.month < rhs.month }
        return lhs.day < rhs.day
    }

    public static func parseIso(_ raw: String) -> SimpleDate? {
        let prefix = String(raw.prefix(10))
        let parts = prefix.split(separator: "-")
        guard parts.count == 3, let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]) else { return nil }
        return SimpleDate(year: year, month: month, day: day)
    }
}
