import Foundation

public struct FeedbackConfig: Codable {
    public struct RatingConfig: Codable {
        public var style: String = "star"
        public var scale: Int = 5
        public init(style: String = "star", scale: Int = 5) { self.style = style; self.scale = scale }
    }

    public struct FeedbackField: Codable {
        public var id: String
        public var type: String
        public var label: String?
        public var required: Bool = false
        public var placeholder: String?
        public var subtext: String?
        public var options: JSONValue?
        public var rows: JSONValue?
        public var columns: JSONValue?
        public var scaleMax: Int?

        public init(
            id: String, type: String, label: String? = nil, required: Bool = false, placeholder: String? = nil,
            subtext: String? = nil, options: JSONValue? = nil, rows: JSONValue? = nil, columns: JSONValue? = nil,
            scaleMax: Int? = nil
        ) {
            self.id = id; self.type = type; self.label = label; self.required = required
            self.placeholder = placeholder; self.subtext = subtext; self.options = options
            self.rows = rows; self.columns = columns; self.scaleMax = scaleMax
        }
    }

    public struct FeedbackFormDefinition: Codable {
        public var id: String?
        public var title: String?
        public var widgetTitle: String?
        public var twoColumnLayout: Bool = false
        public var fields: [FeedbackField] = []

        public init(id: String? = nil, title: String? = nil, widgetTitle: String? = nil, twoColumnLayout: Bool = false, fields: [FeedbackField] = []) {
            self.id = id; self.title = title; self.widgetTitle = widgetTitle
            self.twoColumnLayout = twoColumnLayout; self.fields = fields
        }
    }

    public struct TriggerCondition: Codable {
        public var type: String = "rating"
        public var op: String
        public var value: Double?
        public var min: Double?
        public var max: Double?

        public init(type: String = "rating", op: String, value: Double? = nil, min: Double? = nil, max: Double? = nil) {
            self.type = type; self.op = op; self.value = value; self.min = min; self.max = max
        }
    }

    public struct TriggerRule: Codable {
        public var id: String?
        public var priority: Int = 0
        public var condition: TriggerCondition
        public var formId: String

        public init(id: String? = nil, priority: Int = 0, condition: TriggerCondition, formId: String) {
            self.id = id; self.priority = priority; self.condition = condition; self.formId = formId
        }
    }

    public var rating: RatingConfig?
    public var forms: [String: FeedbackFormDefinition] = [:]
    public var trigger_rules: [TriggerRule] = []
    public var show_default_form: Bool = false

    public init(rating: RatingConfig? = nil, forms: [String: FeedbackFormDefinition] = [:], trigger_rules: [TriggerRule] = [], show_default_form: Bool = false) {
        self.rating = rating; self.forms = forms; self.trigger_rules = trigger_rules; self.show_default_form = show_default_form
    }
}

public struct FeedbackOption: Equatable {
    public let value: String
    public let label: String
    public init(value: String, label: String) { self.value = value; self.label = label }
}

private let feedbackFieldTypeAliases: [String: String] = [
    "text": "textbox",
    "input": "textbox",
    "select": "dropdown",
    "date-picker": "date",
    "datepicker": "date",
    "file-upload": "file",
    "fileupload": "file",
    "checkbox-matrix": "checkbox-matrix",
    "radio-matrix": "radio-matrix",
    "rank-scale": "rank",
    "scale": "rank",
]

public func normalizeFeedbackFieldType(_ type: String) -> String {
    let key = type.lowercased().trimmingCharacters(in: .whitespaces)
        .replacingOccurrences(of: "_", with: "-")
        .replacingOccurrences(of: "\\s+", with: "-", options: .regularExpression)
    return feedbackFieldTypeAliases[key] ?? key
}

public func normalizeFeedbackOptions(_ options: JSONValue?) -> [FeedbackOption] {
    guard let array = options?.arrayValue else { return [] }
    return array.enumerated().compactMap { index, element in
        switch element {
        case .object(let obj):
            let id = obj["id"]?.contentOrNull ?? "opt_\(index)"
            let label = obj["label"]?.contentOrNull ?? id
            return FeedbackOption(value: id, label: label)
        case .null:
            return nil
        default:
            guard let content = element.contentOrNull else { return nil }
            return FeedbackOption(value: content, label: content)
        }
    }
}

public func normalizeFeedbackMatrixItems(_ items: JSONValue?) -> [FeedbackOption] {
    guard let array = items?.arrayValue else { return [] }
    return array.enumerated().map { index, element in
        switch element {
        case .object(let obj):
            let id = obj["id"]?.contentOrNull ?? "item_\(index)"
            let label = obj["label"]?.contentOrNull ?? id
            return FeedbackOption(value: id, label: label)
        default:
            if let content = element.contentOrNull {
                return FeedbackOption(value: "row_\(index)", label: content)
            }
            return FeedbackOption(value: "row_\(index)", label: "Item \(index + 1)")
        }
    }
}

public func resolveFeedbackFormId(rating: Int, rules: [FeedbackConfig.TriggerRule]) -> String? {
    let sorted = rules.sorted { $0.priority < $1.priority }
    return sorted.first { rule in
        let condition = rule.condition
        guard condition.type == "rating" else { return false }
        switch condition.op {
        case "<=": return condition.value.map { Double(rating) <= $0 } ?? false
        case "=": return condition.value.map { Double(rating) == $0 } ?? false
        case ">=": return condition.value.map { Double(rating) >= $0 } ?? false
        case "between":
            guard let min = condition.min, let max = condition.max else { return false }
            return Double(rating) >= min && Double(rating) <= max
        default: return false
        }
    }?.formId
}

extension FeedbackConfig {
    public func activeForm(_ formId: String?) -> FeedbackFormDefinition? {
        guard let formId else { return nil }
        if formId == "none" {
            return forms["none"] ?? FeedbackFormDefinition(id: "none")
        }
        return forms[formId]
    }
}
