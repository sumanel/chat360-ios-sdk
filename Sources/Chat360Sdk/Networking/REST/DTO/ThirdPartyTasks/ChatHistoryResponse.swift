import Foundation

struct ChatHistoryEnvelope: Decodable {
    var success: Bool = false
    var data: ChatHistoryResponse?
}

struct ChatHistoryResponse: Decodable {
    var room_id: String
    var session_id: String
    var messages: [ChatHistoryMessage] = []
    var total_count: Int = 0
    var has_more: Bool = false
}

struct ChatHistoryMessage: Codable {
    var text: String
    var sender_id: String
    var timestamp: String
    var message_id: String
    var sender_type: String
    var message_type: String
}
