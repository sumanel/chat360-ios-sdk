import XCTest
@testable import Chat360SDK

final class DateAvailabilityTests: XCTestCase {

    private func today() -> SimpleDate { SimpleDate.today() }

    private func addingDays(_ days: Int, to date: SimpleDate) -> SimpleDate {
        var comps = DateComponents()
        comps.year = date.year
        comps.month = date.month
        comps.day = date.day + days
        let calendar = SimpleDate.utcCalendar
        let foundationDate = calendar.date(from: comps)!
        let result = calendar.dateComponents([.year, .month, .day], from: foundationDate)
        return SimpleDate(year: result.year!, month: result.month!, day: result.day!)
    }

    func testDisableFutureBlocksDatesAfterToday() {
        let rules = DateRules(disableFuture: true)
        XCTAssertTrue(DateAvailability.isDisabled(rules, addingDays(1, to: today())))
        XCTAssertFalse(DateAvailability.isDisabled(rules, today()))
        XCTAssertFalse(DateAvailability.isDisabled(rules, addingDays(-1, to: today())))
    }

    func testDisablePreviousBlocksDatesBeforeToday() {
        let rules = DateRules(disablePrevious: true)
        XCTAssertTrue(DateAvailability.isDisabled(rules, addingDays(-1, to: today())))
        XCTAssertFalse(DateAvailability.isDisabled(rules, today()))
    }

    func testIsScheduledDateBlocksTheConfiguredWeekdaySundayIndex0() {
        let sunday = SimpleDate(year: 2026, month: 8, day: 2) // a Sunday
        let rules = DateRules(isScheduledDate: true, disabledDays: [true, false, false, false, false, false, false])
        XCTAssertTrue(DateAvailability.isDisabled(rules, sunday))
        XCTAssertFalse(DateAvailability.isDisabled(rules, addingDays(1, to: sunday))) // Monday
    }

    func testIsScheduledDateBlocksExplicitDisabledDates() {
        let rules = DateRules(isScheduledDate: true, disabledDates: ["2026-08-15"])
        XCTAssertTrue(DateAvailability.isDisabled(rules, SimpleDate(year: 2026, month: 8, day: 15)))
        XCTAssertFalse(DateAvailability.isDisabled(rules, SimpleDate(year: 2026, month: 8, day: 16)))
    }

    func testManageWithVariableDisableInVarBlocksOnlyListedDates() {
        let rules = DateRules(manageWithVariable: true, variableMode: "disable_in_var", variableDates: ["2026-09-01"])
        XCTAssertTrue(DateAvailability.isDisabled(rules, SimpleDate(year: 2026, month: 9, day: 1)))
        XCTAssertFalse(DateAvailability.isDisabled(rules, SimpleDate(year: 2026, month: 9, day: 2)))
    }

    func testManageWithVariableDisableNotInVarBlocksEverythingExceptListedDates() {
        let rules = DateRules(manageWithVariable: true, variableMode: "disable_not_in_var", variableDates: ["2026-09-01"])
        XCTAssertFalse(DateAvailability.isDisabled(rules, SimpleDate(year: 2026, month: 9, day: 1)))
        XCTAssertTrue(DateAvailability.isDisabled(rules, SimpleDate(year: 2026, month: 9, day: 2)))
    }

    func testParseAndFormatRoundTripADayjsStylePattern() {
        let date = SimpleDate(year: 2026, month: 8, day: 15)
        let formatted = DateAvailability.format(date, pattern: "DD MMM YYYY")
        XCTAssertEqual(formatted, "15 Aug 2026")
        XCTAssertEqual(DateAvailability.parse(formatted, pattern: "DD MMM YYYY"), date)
    }
}
