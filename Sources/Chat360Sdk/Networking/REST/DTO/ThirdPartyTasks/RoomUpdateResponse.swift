import Foundation

public struct RoomUpdateEnvelope: Codable {
    public var success: Bool = false
    public var data: RoomUpdateResponse?

    public init(success: Bool = false, data: RoomUpdateResponse? = nil) {
        self.success = success
        self.data = data
    }

    enum CodingKeys: String, CodingKey {
        case success, data
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        success = try container.decode(Bool.self, forKey: .success, default: false)
        data = try container.decodeIfPresent(RoomUpdateResponse.self, forKey: .data)
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

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        roomId = try container.decode(String.self, forKey: .roomId)
        roomName = try container.decode(String.self, forKey: .roomName, default: "")
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt)
    }
}
