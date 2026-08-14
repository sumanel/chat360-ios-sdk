import Foundation

public struct FeedbackConfig: Codable {
    public struct RatingConfig: Codable {
        public var style: String = "star"
        public var scale: Int = 5
        public init(style: String = "star", scale: Int = 5) { self.style = style; self.scale = scale }

        enum CodingKeys: String, CodingKey { case style, scale }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            style = try container.decode(String.self, forKey: .style, default: "star")
            scale = try container.decode(Int.self, forKey: .scale, default: 5)
        }
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

        enum CodingKeys: String, CodingKey { case id, type, label, required, placeholder, subtext, options, rows, columns, scaleMax }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(String.self, forKey: .id)
            type = try container.decode(String.self, forKey: .type)
            label = try container.decodeIfPresent(String.self, forKey: .label)
            required = try container.decode(Bool.self, forKey: .required, default: false)
            placeholder = try container.decodeIfPresent(String.self, forKey: .placeholder)
            subtext = try container.decodeIfPresent(String.self, forKey: .subtext)
            options = try container.decodeIfPresent(JSONValue.self, forKey: .options)
            rows = try container.decodeIfPresent(JSONValue.self, forKey: .rows)
            columns = try container.decodeIfPresent(JSONValue.self, forKey: .columns)
            scaleMax = try container.decodeIfPresent(Int.self, forKey: .scaleMax)
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

        enum CodingKeys: String, CodingKey { case id, title, widgetTitle, twoColumnLayout, fields }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decodeIfPresent(String.self, forKey: .id)
            title = try container.decodeIfPresent(String.self, forKey: .title)
            widgetTitle = try container.decodeIfPresent(String.self, forKey: .widgetTitle)
            twoColumnLayout = try container.decode(Bool.self, forKey: .twoColumnLayout, default: false)
            fields = try container.decode([FeedbackField].self, forKey: .fields, default: [])
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

        enum CodingKeys: String, CodingKey { case type, op, value, min, max }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            type = try container.decode(String.self, forKey: .type, default: "rating")
            op = try container.decode(String.self, forKey: .op)
            value = try container.decodeIfPresent(Double.self, forKey: .value)
            min = try container.decodeIfPresent(Double.self, forKey: .min)
            max = try container.decodeIfPresent(Double.self, forKey: .max)
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

        enum CodingKeys: String, CodingKey { case id, priority, condition, formId }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decodeIfPresent(String.self, forKey: .id)
            priority = try container.decode(Int.self, forKey: .priority, default: 0)
            condition = try container.decode(TriggerCondition.self, forKey: .condition)
            formId = try container.decode(String.self, forKey: .formId)
        }
    }

    public var rating: RatingConfig?
    public var forms: [String: FeedbackFormDefinition] = [:]
    public var trigger_rules: [TriggerRule] = []
    public var show_default_form: Bool = false

    public init(rating: RatingConfig? = nil, forms: [String: FeedbackFormDefinition] = [:], trigger_rules: [TriggerRule] = [], show_default_form: Bool = false) {
        self.rating = rating; self.forms = forms; self.trigger_rules = trigger_rules; self.show_default_form = show_default_form
    }

    enum CodingKeys: String, CodingKey { case rating, forms, trigger_rules, show_default_form }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        rating = try container.decodeIfPresent(RatingConfig.self, forKey: .rating)
        forms = try container.decode([String: FeedbackFormDefinition].self, forKey: .forms, default: [:])
        trigger_rules = try container.decode([TriggerRule].self, forKey: .trigger_rules, default: [])
        show_default_form = try container.decode(Bool.self, forKey: .show_default_form, default: false)
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
