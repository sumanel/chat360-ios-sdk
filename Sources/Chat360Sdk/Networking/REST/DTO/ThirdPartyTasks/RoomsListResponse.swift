import Foundation

public struct RoomsListEnvelope: Codable {
    public var success: Bool = false
    public var data: RoomsListResponse?

    public init(success: Bool = false, data: RoomsListResponse? = nil) {
        self.success = success
        self.data = data
    }
}

public struct RoomsListResponse: Codable {
    public var clientId: String?
    public var botId: String?
    public var rooms: [RoomDto] = []
    public var totalCount: Int = 0
    public var hasMore: Bool = false

    enum CodingKeys: String, CodingKey {
        case clientId = "client_id"
        case botId = "bot_id"
        case rooms
        case totalCount = "total_count"
        case hasMore = "has_more"
    }

    public init(clientId: String? = nil, botId: String? = nil, rooms: [RoomDto] = [], totalCount: Int = 0, hasMore: Bool = false) {
        self.clientId = clientId
        self.botId = botId
        self.rooms = rooms
        self.totalCount = totalCount
        self.hasMore = hasMore
    }
}

public struct RoomDto: Codable {
    public var roomId: String
    public var roomName: String = ""
    public var agentId: String?
    public var status: String?
    public var createdAt: String?
    public var updatedAt: String?
    public var sessionIds: [String] = []
    public var sessionCount: Int = 0

    enum CodingKeys: String, CodingKey {
        case roomId = "room_id"
        case roomName = "room_name"
        case agentId = "agent_id"
        case status
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case sessionIds = "session_ids"
        case sessionCount = "session_count"
    }

    public init(
        roomId: String, roomName: String = "", agentId: String? = nil, status: String? = nil,
        createdAt: String? = nil, updatedAt: String? = nil, sessionIds: [String] = [], sessionCount: Int = 0
    ) {
        self.roomId = roomId
        self.roomName = roomName
        self.agentId = agentId
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.sessionIds = sessionIds
        self.sessionCount = sessionCount
    }
}
