import Foundation

/// A loose, dynamically-typed JSON value. Used wherever the wire models decode into a raw JSON
/// tree and walk it manually (bot node payloads, form field validation blobs, feedback field
/// options) rather than a fixed `Codable` shape, since the server's node payloads vary per
/// `nodeType` and aren't worth a struct per shape.
public indirect enum JSONValue: Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null
}

extension JSONValue: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let number = try? container.decode(Double.self) {
            self = .number(number)
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let array = try? container.decode([JSONValue].self) {
            self = .array(array)
        } else if let object = try? container.decode([String: JSONValue].self) {
            self = .object(object)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}

// MARK: - Dynamic access helpers (`string(key)`, `boolean(key)`, `int(key)`, `double(key)`).

public extension JSONValue {
    subscript(key: String) -> JSONValue? {
        if case .object(let dict) = self { return dict[key] }
        return nil
    }

    var objectValue: [String: JSONValue]? {
        if case .object(let dict) = self { return dict }
        return nil
    }

    var arrayValue: [JSONValue]? {
        if case .array(let items) = self { return items }
        return nil
    }

    var isEmptyObject: Bool {
        if case .object(let dict) = self { return dict.isEmpty }
        return false
    }

    func containsKey(_ key: String) -> Bool {
        if case .object(let dict) = self { return dict[key] != nil }
        return false
    }

    /// The raw string form of a string/number/bool leaf, or nil for object/array/null/missing.
    var contentOrNull: String? {
        switch self {
        case .string(let value): return value
        case .number(let value):
            if value == value.rounded() && abs(value) < 1e15 { return String(Int64(value)) }
            return String(value)
        case .bool(let value): return value ? "true" : "false"
        case .object, .array, .null: return nil
        }
    }

    var boolOrNull: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }

    func string(_ key: String) -> String? {
        self[key]?.contentOrNull
    }

    /// A true JSON boolean, or the string "1".
    func boolean(_ key: String) -> Bool {
        guard let value = self[key] else { return false }
        return value.boolOrNull ?? (value.contentOrNull == "1")
    }

    func int(_ key: String) -> Int? {
        guard let content = self[key]?.contentOrNull else { return nil }
        return Double(content).map { Int($0) }
    }

    func double(_ key: String) -> Double? {
        guard let content = self[key]?.contentOrNull else { return nil }
        return Double(content)
    }
}

public extension Array where Element == JSONValue {
    func stringsOrNull() -> [String?] {
        map { $0.contentOrNull }
    }
}

public extension JSONValue {
    /// Parses raw JSON text (e.g. one WebSocket frame) into a `JSONValue` tree.
    static func parse(_ text: String) -> JSONValue? {
        guard let data = text.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(JSONValue.self, from: data)
    }
}
