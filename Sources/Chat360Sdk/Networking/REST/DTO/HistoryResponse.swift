import Foundation

/// `history` items decode as `RawSocketEnvelope` because history entries and live socket
/// messages share one wire shape - both go through the exact same `toIncomingEvent()`.
struct HistoryResponse: Decodable {
    var history: [RawSocketEnvelope] = []
    var current_length: Int?
    var next_cursor: Int?
    var previous_cursor: Int?

    /// Empty-response fallback for a disabled/failed history fetch.
    init() {}

    private enum CodingKeys: String, CodingKey { case history, current_length, next_cursor, previous_cursor }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        history = try c.decodeIfPresent([RawSocketEnvelope].self, forKey: .history) ?? []
        current_length = try c.decodeIfPresent(Int.self, forKey: .current_length)
        next_cursor = try c.decodeIfPresent(Int.self, forKey: .next_cursor)
        previous_cursor = try c.decodeIfPresent(Int.self, forKey: .previous_cursor)
    }
}
