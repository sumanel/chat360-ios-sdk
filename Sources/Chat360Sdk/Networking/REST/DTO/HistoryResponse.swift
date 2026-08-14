import Foundation

public struct HistoryResponse: Codable {
    public var history: [RawSocketEnvelope] = []
    public var current_length: Int?
    public var next_cursor: Int?
    public var previous_cursor: Int?

    public init(history: [RawSocketEnvelope] = [], current_length: Int? = nil, next_cursor: Int? = nil, previous_cursor: Int? = nil) {
        self.history = history
        self.current_length = current_length
        self.next_cursor = next_cursor
        self.previous_cursor = previous_cursor
    }

    enum CodingKeys: String, CodingKey {
        case history, current_length, next_cursor, previous_cursor
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        history = try container.decode([RawSocketEnvelope].self, forKey: .history, default: [])
        current_length = try container.decodeIfPresent(Int.self, forKey: .current_length)
        next_cursor = try container.decodeIfPresent(Int.self, forKey: .next_cursor)
        previous_cursor = try container.decodeIfPresent(Int.self, forKey: .previous_cursor)
    }
}
