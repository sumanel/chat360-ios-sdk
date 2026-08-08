import Foundation

struct RoomUpdateEnvelope: Decodable {
    var success: Bool = false
    var data: RoomUpdateResponse?
}

struct RoomUpdateResponse: Decodable {
    var room_id: String
    var room_name: String = ""
    var updated_at: String?
}
