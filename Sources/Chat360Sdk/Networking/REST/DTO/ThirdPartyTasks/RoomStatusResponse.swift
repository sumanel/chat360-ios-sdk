import Foundation

public struct RoomStatusEnvelope: Codable {
    public var success: Bool = false
    public var data: RoomStatusResponse?

    public init(success: Bool = false, data: RoomStatusResponse? = nil) {
        self.success = success
        self.data = data
    }

    enum CodingKeys: String, CodingKey {
        case success, data
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        success = try container.decode(Bool.self, forKey: .success, default: false)
        data = try container.decodeIfPresent(RoomStatusResponse.self, forKey: .data)
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

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        roomId = try container.decode(String.self, forKey: .roomId)
        status = try container.decode(String.self, forKey: .status, default: "")
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt)
    }
}
