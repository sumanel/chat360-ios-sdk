import Foundation

public struct RoomStatusEnvelope: Codable {
    public var success: Bool = false
    public var data: RoomStatusResponse?

    public init(success: Bool = false, data: RoomStatusResponse? = nil) {
        self.success = success
        self.data = data
    }
}

public struct RoomStatusResponse: Codable {
    public var roomId: String
    public var status: String = ""
    public var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case roomId = "room_id"
        case status
        case updatedAt = "updated_at"
    }

    public init(roomId: String, status: String = "", updatedAt: String? = nil) {
        self.roomId = roomId
        self.status = status
        self.updatedAt = updatedAt
    }
}
