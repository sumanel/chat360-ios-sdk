import Foundation

public indirect enum JSONValue: Equatable {
    case object([String: JSONValue])
    case array([JSONValue])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    public var objectValue: [String: JSONValue]? {
        if case .object(let value) = self { return value }
        return nil
    }

    public var arrayValue: [JSONValue]? {
        if case .array(let value) = self { return value }
        return nil
    }

    public var stringValue: String? {
        switch self {
        case .string(let value): return value
        default: return nil
        }
    }

    public var boolValue: Bool? {
        switch self {
        case .bool(let value): return value
        case .string(let value): return value == "1" ? true : nil
        default: return nil
        }
    }

    public var contentOrNull: String? {
        switch self {
        case .string(let value): return value
        case .number(let value):
            if value == value.rounded() && abs(value) < 1e15 {
                return String(Int64(value))
            }
            return String(value)
        case .bool(let value): return value ? "true" : "false"
        case .null: return nil
        default: return nil
        }
    }

    public var doubleValue: Double? {
        switch self {
        case .number(let value): return value
        case .string(let value): return Double(value)
        default: return nil
        }
    }

    public var intValue: Int? {
        guard let doubleValue else { return nil }
        return Int(doubleValue)
    }

    public subscript(key: String) -> JSONValue? {
        objectValue?[key]
    }

    public func containsKey(_ key: String) -> Bool {
        objectValue?[key] != nil
    }
}

extension JSONValue: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else {
            self = .null
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}

extension JSONValue {
    public static func from(_ any: Any?) -> JSONValue {
        guard let any, !(any is NSNull) else { return .null }
        switch any {
        case let value as String: return .string(value)
        case let value as Bool: return .bool(value)
        case let value as Int: return .number(Double(value))
        case let value as Double: return .number(value)
        case let value as [String: Any]:
            var result: [String: JSONValue] = [:]
            for (key, nested) in value { result[key] = JSONValue.from(nested) }
            return .object(result)
        case let value as [Any]:
            return .array(value.map { JSONValue.from($0) })
        default:
            return .null
        }
    }

    public func toFoundation() -> Any {
        switch self {
        case .object(let value):
            var result: [String: Any] = [:]
            for (key, nested) in value { result[key] = nested.toFoundation() }
            return result
        case .array(let value): return value.map { $0.toFoundation() }
        case .string(let value): return value
        case .number(let value): return value
        case .bool(let value): return value
        case .null: return NSNull()
        }
    }
}
