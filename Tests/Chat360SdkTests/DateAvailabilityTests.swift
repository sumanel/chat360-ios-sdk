import XCTest
@testable import Chat360SDK

final class DateAvailabilityTests: XCTestCase {
    private func offset(_ days: Int, from date: SimpleDate = .today()) -> SimpleDate {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        var components = DateComponents()
        components.year = date.year
        components.month = date.month
        components.day = date.day
        let base = calendar.date(from: components)!
        let shifted = calendar.date(byAdding: .day, value: days, to: base)!
        let shiftedComponents = calendar.dateComponents([.year, .month, .day], from: shifted)
        return SimpleDate(year: shiftedComponents.year!, month: shiftedComponents.month!, day: shiftedComponents.day!)
    }

    func testDisableFutureBlocksDatesAfterToday() {
        var rules = DateRules()
        rules.disableFuture = true
        XCTAssertTrue(DateAvailability.isDisabled(rules, date: offset(1)))
        XCTAssertFalse(DateAvailability.isDisabled(rules, date: .today()))
        XCTAssertFalse(DateAvailability.isDisabled(rules, date: offset(-1)))
    }

    func testDisablePreviousBlocksDatesBeforeToday() {
        var rules = DateRules()
        rules.disablePrevious = true
        XCTAssertTrue(DateAvailability.isDisabled(rules, date: offset(-1)))
        XCTAssertFalse(DateAvailability.isDisabled(rules, date: .today()))
    }

    func testScheduledDateBlocksConfiguredWeekdaySundayIndexZero() {
        let sunday = SimpleDate(year: 2026, month: 8, day: 2)
        var rules = DateRules()
        rules.isScheduledDate = true
        rules.disabledDays = [true, false, false, false, false, false, false]
        XCTAssertTrue(DateAvailability.isDisabled(rules, date: sunday))
        XCTAssertFalse(DateAvailability.isDisabled(rules, date: offset(1, from: sunday)))
    }

    func testScheduledDateBlocksExplicitDisabledDates() {
        var rules = DateRules()
        rules.isScheduledDate = true
        rules.disabledDates = ["2026-08-15"]
        XCTAssertTrue(DateAvailability.isDisabled(rules, date: SimpleDate(year: 2026, month: 8, day: 15)))
        XCTAssertFalse(DateAvailability.isDisabled(rules, date: SimpleDate(year: 2026, month: 8, day: 16)))
    }

    func testManageWithVariableDisableInVarBlocksOnlyListedDates() {
        var rules = DateRules()
        rules.manageWithVariable = true
        rules.variableMode = "disable_in_var"
        rules.variableDates = ["2026-09-01"]
        XCTAssertTrue(DateAvailability.isDisabled(rules, date: SimpleDate(year: 2026, month: 9, day: 1)))
        XCTAssertFalse(DateAvailability.isDisabled(rules, date: SimpleDate(year: 2026, month: 9, day: 2)))
    }

    func testManageWithVariableDisableNotInVarBlocksEverythingExceptListedDates() {
        var rules = DateRules()
        rules.manageWithVariable = true
        rules.variableMode = "disable_not_in_var"
        rules.variableDates = ["2026-09-01"]
        XCTAssertFalse(DateAvailability.isDisabled(rules, date: SimpleDate(year: 2026, month: 9, day: 1)))
        XCTAssertTrue(DateAvailability.isDisabled(rules, date: SimpleDate(year: 2026, month: 9, day: 2)))
    }

    func testParseAndFormatRoundTripADayjsStylePattern() {
        let date = SimpleDate(year: 2026, month: 8, day: 15)
        let formatted = DateAvailability.format(date, pattern: "DD MMM YYYY")
        XCTAssertEqual(formatted, "15 Aug 2026")
        XCTAssertEqual(DateAvailability.parse(formatted, pattern: "DD MMM YYYY"), date)
    }
}
