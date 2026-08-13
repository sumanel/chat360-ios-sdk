import Foundation

public struct RoomUpdateEnvelope: Codable {
    public var success: Bool = false
    public var data: RoomUpdateResponse?

    public init(success: Bool = false, data: RoomUpdateResponse? = nil) {
        self.success = success
        self.data = data
    }
}

public struct RoomUpdateResponse: Codable {
    public var roomId: String
    public var roomName: String = ""
    public var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case roomId = "room_id"
        case roomName = "room_name"
        case updatedAt = "updated_at"
    }

    public init(roomId: String, roomName: String = "", updatedAt: String? = nil) {
        self.roomId = roomId
        self.roomName = roomName
        self.updatedAt = updatedAt
    }
}
