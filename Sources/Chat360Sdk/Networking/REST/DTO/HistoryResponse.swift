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
}
