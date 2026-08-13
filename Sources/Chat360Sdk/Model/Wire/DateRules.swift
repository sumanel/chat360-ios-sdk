import Foundation

public struct DateRules: Equatable {
    public var isScheduledDate: Bool = false
    public var disabledDays: [Bool]?
    public var disabledDates: [String]?
    public var disableFuture: Bool = false
    public var disableCurrent: Bool = false
    public var disablePrevious: Bool = false
    public var manageWithVariable: Bool = false
    public var variableMode: String?
    public var variableDates: [String]?
    public var dateFormat: String = "DD MMM YYYY"

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
