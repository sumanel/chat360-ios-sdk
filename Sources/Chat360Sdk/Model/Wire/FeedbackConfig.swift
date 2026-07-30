import Foundation

/// The bot-owner-authored, config-driven post-chat survey (rating plus a form whose exact fields
/// depend on which ``TriggerRule`` the rating matched). Arrives as part of the same appearance
/// blob the bot's appearance API already returns.
public struct FeedbackConfig: Codable, Equatable {
    public struct RatingConfig: Codable, Equatable {
        public var style: String = "star"
        public var scale: Int = 5

        private enum CodingKeys: String, CodingKey { case style, scale }
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            style = try c.decodeIfPresent(String.self, forKey: .style) ?? "star"
            scale = try c.decodeIfPresent(Int.self, forKey: .scale) ?? 5
        }
    }

    public struct FeedbackFormDefinition: Codable, Equatable {
        public var id: String?
        public var title: String?
        public var widgetTitle: String?
        public var twoColumnLayout: Bool = false
        public var fields: [FeedbackField] = []

        public init(id: String? = nil, title: String? = nil, widgetTitle: String? = nil, twoColumnLayout: Bool = false, fields: [FeedbackField] = []) {
            self.id = id
            self.title = title
            self.widgetTitle = widgetTitle
            self.twoColumnLayout = twoColumnLayout
            self.fields = fields
        }

        private enum CodingKeys: String, CodingKey { case id, title, widgetTitle, twoColumnLayout, fields }
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decodeIfPresent(String.self, forKey: .id)
            title = try c.decodeIfPresent(String.self, forKey: .title)
            widgetTitle = try c.decodeIfPresent(String.self, forKey: .widgetTitle)
            twoColumnLayout = try c.decodeIfPresent(Bool.self, forKey: .twoColumnLayout) ?? false
            fields = try c.decodeIfPresent([FeedbackField].self, forKey: .fields) ?? []
        }
    }

    /// `options`/`rows`/`columns` are heterogeneous on the wire (a bare `[String]` or an
    /// `[{id,label}]`) - kept as raw `JSONValue` and normalized at the call site via
    /// `normalizeFeedbackOptions`/`normalizeFeedbackMatrixItems`.
    public struct FeedbackField: Codable, Equatable {
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

        private enum CodingKeys: String, CodingKey { case id, type, label, required, placeholder, subtext, options, rows, columns, scaleMax }
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(String.self, forKey: .id)
            type = try c.decode(String.self, forKey: .type)
            label = try c.decodeIfPresent(String.self, forKey: .label)
            required = try c.decodeIfPresent(Bool.self, forKey: .required) ?? false
            placeholder = try c.decodeIfPresent(String.self, forKey: .placeholder)
            subtext = try c.decodeIfPresent(String.self, forKey: .subtext)
            options = try c.decodeIfPresent(JSONValue.self, forKey: .options)
            rows = try c.decodeIfPresent(JSONValue.self, forKey: .rows)
            columns = try c.decodeIfPresent(JSONValue.self, forKey: .columns)
            scaleMax = try c.decodeIfPresent(Int.self, forKey: .scaleMax)
        }
    }

    public struct TriggerRule: Codable, Equatable {
        public var id: String?
        public var priority: Int = 0
        public var condition: TriggerCondition
        public var formId: String

        private enum CodingKeys: String, CodingKey { case id, priority, condition, formId }
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decodeIfPresent(String.self, forKey: .id)
            priority = try c.decodeIfPresent(Int.self, forKey: .priority) ?? 0
            condition = try c.decode(TriggerCondition.self, forKey: .condition)
            formId = try c.decode(String.self, forKey: .formId)
        }
    }

    public struct TriggerCondition: Codable, Equatable {
        public var type: String = "rating"
        public var op: String
        public var value: Double?
        public var min: Double?
        public var max: Double?

        private enum CodingKeys: String, CodingKey { case type, op, value, min, max }
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            type = try c.decodeIfPresent(String.self, forKey: .type) ?? "rating"
            op = try c.decode(String.self, forKey: .op)
            value = try c.decodeIfPresent(Double.self, forKey: .value)
            min = try c.decodeIfPresent(Double.self, forKey: .min)
            max = try c.decodeIfPresent(Double.self, forKey: .max)
        }
    }

    public var rating: RatingConfig?
    public var forms: [String: FeedbackFormDefinition] = [:]
    public var trigger_rules: [TriggerRule] = []
    public var show_default_form: Bool = false

    private enum CodingKeys: String, CodingKey { case rating, forms, trigger_rules, show_default_form }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        rating = try c.decodeIfPresent(RatingConfig.self, forKey: .rating)
        forms = try c.decodeIfPresent([String: FeedbackFormDefinition].self, forKey: .forms) ?? [:]
        trigger_rules = try c.decodeIfPresent([TriggerRule].self, forKey: .trigger_rules) ?? []
        show_default_form = try c.decodeIfPresent(Bool.self, forKey: .show_default_form) ?? false
    }
}

public struct FeedbackOption: Equatable {
    public var value: String
    public var label: String
}

/// Aliases/underscore-vs-hyphen variants collapse onto one canonical id.
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
        .replacingOccurrences(of: #"\s+"#, with: "-", options: .regularExpression)
    return feedbackFieldTypeAliases[key] ?? key
}

/// A field's flat choice list (dropdown/radio/checkbox).
public func normalizeFeedbackOptions(_ options: JSONValue?) -> [FeedbackOption] {
    guard let array = options?.arrayValue else { return [] }
    return array.enumerated().compactMap { index, element in
        switch element {
        case .string(let value):
            return FeedbackOption(value: value, label: value)
        case .number, .bool:
            guard let content = element.contentOrNull else { return nil }
            return FeedbackOption(value: content, label: content)
        case .object:
            let id = element.string("id") ?? "opt_\(index)"
            let label = element.string("label") ?? id
            return FeedbackOption(value: id, label: label)
        case .array, .null:
            return nil
        }
    }
}

/// A matrix field's rows/columns.
public func normalizeFeedbackMatrixItems(_ items: JSONValue?) -> [FeedbackOption] {
    guard let array = items?.arrayValue else { return [] }
    return array.enumerated().map { index, element in
        switch element {
        case .string(let value):
            return FeedbackOption(value: "row_\(index)", label: value)
        case .number, .bool:
            let content = element.contentOrNull ?? "Item \(index + 1)"
            return FeedbackOption(value: "row_\(index)", label: content)
        case .object:
            let id = element.string("id") ?? "item_\(index)"
            let label = element.string("label") ?? id
            return FeedbackOption(value: id, label: label)
        case .array, .null:
            return FeedbackOption(value: "row_\(index)", label: "Item \(index + 1)")
        }
    }
}

/// First matching rule by ascending priority, or nil (no form) if none match.
public func resolveFeedbackFormId(rating: Int, rules: [FeedbackConfig.TriggerRule]) -> String? {
    rules.sorted { $0.priority < $1.priority }.first { rule in
        let condition = rule.condition
        guard condition.type == "rating" else { return false }
        switch condition.op {
        case "<=":
            guard let value = condition.value else { return false }
            return Double(rating) <= value
        case "=":
            guard let value = condition.value else { return false }
            return Double(rating) == value
        case ">=":
            guard let value = condition.value else { return false }
            return Double(rating) >= value
        case "between":
            guard let min = condition.min, let max = condition.max else { return false }
            return Double(rating) >= min && Double(rating) <= max
        default:
            return false
        }
    }?.formId
}

public extension FeedbackConfig {
    /// `'none'` resolves to an explicit empty form even if `forms.none` is absent, so a
    /// matched-but-form-less rule renders nothing rather than falling back to the default form.
    func activeForm(_ formId: String?) -> FeedbackFormDefinition? {
        guard let formId else { return nil }
        if formId == "none" {
            return forms["none"] ?? FeedbackFormDefinition(id: "none")
        }
        return forms[formId]
    }
}
