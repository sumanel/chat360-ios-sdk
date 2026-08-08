import Foundation

/// The disabled-date rule set shared by standalone DATE prompts and FORM DATE fields. Two rarer
/// rules are intentionally not supported here (a known gap, not silently dropped): the
/// "referredDate" fencing relative to another variable's date, and the
/// disabledDaysFromCd/onlyEnableDaysFromCd rolling-window-from-today variants.
public struct DateRules: Equatable {
    public var isScheduledDate: Bool
    /// index 0 = Sunday .. 6 = Saturday, only honored when `isScheduledDate` is true.
    public var disabledDays: [Bool]?
    public var disabledDates: [String]?
    public var disableFuture: Bool
    public var disableCurrent: Bool
    public var disablePrevious: Bool
    public var manageWithVariable: Bool
    public var variableMode: String?
    public var variableDates: [String]?
    /// Dayjs-style pattern as received on the wire (e.g. "DD MMM YYYY") - converted at parse time.
    public var dateFormat: String

    public init(
        isScheduledDate: Bool = false,
        disabledDays: [Bool]? = nil,
        disabledDates: [String]? = nil,
        disableFuture: Bool = false,
        disableCurrent: Bool = false,
        disablePrevious: Bool = false,
        manageWithVariable: Bool = false,
        variableMode: String? = nil,
        variableDates: [String]? = nil,
        dateFormat: String = "DD MMM YYYY"
    ) {
        self.isScheduledDate = isScheduledDate
        self.disabledDays = disabledDays
        self.disabledDates = disabledDates
        self.disableFuture = disableFuture
        self.disableCurrent = disableCurrent
        self.disablePrevious = disablePrevious
        self.manageWithVariable = manageWithVariable
        self.variableMode = variableMode
        self.variableDates = variableDates
        self.dateFormat = dateFormat
    }
}
