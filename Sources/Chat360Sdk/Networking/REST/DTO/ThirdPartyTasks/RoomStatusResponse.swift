import Foundation

struct RoomStatusEnvelope: Decodable {
    var success: Bool = false
    var data: RoomStatusResponse?
}

struct RoomStatusResponse: Decodable {
    var room_id: String
    var status: String = ""
    var updated_at: String?
}
