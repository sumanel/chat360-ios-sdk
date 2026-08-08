import Foundation

struct RoomsListEnvelope: Decodable {
    var success: Bool = false
    var data: RoomsListResponse?
}

struct RoomsListResponse: Decodable {
    var client_id: String?
    var bot_id: String?
    var rooms: [RoomDto] = []
    var total_count: Int = 0
    var has_more: Bool = false
}

struct RoomDto: Decodable {
    var room_id: String
    var room_name: String = ""
    var agent_id: String?
    var status: String?
    var created_at: String?
    var updated_at: String?
    var session_ids: [String] = []
    var session_count: Int = 0
}
