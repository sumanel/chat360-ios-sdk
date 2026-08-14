import Foundation

public struct RoomsListEnvelope: Codable {
    public var success: Bool = false
    public var data: RoomsListResponse?

    public init(success: Bool = false, data: RoomsListResponse? = nil) {
        self.success = success
        self.data = data
    }

    enum CodingKeys: String, CodingKey {
        case success, data
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        success = try container.decode(Bool.self, forKey: .success, default: false)
        data = try container.decodeIfPresent(RoomsListResponse.self, forKey: .data)
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

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        clientId = try container.decodeIfPresent(String.self, forKey: .clientId)
        botId = try container.decodeIfPresent(String.self, forKey: .botId)
        rooms = try container.decode([RoomDto].self, forKey: .rooms, default: [])
        totalCount = try container.decode(Int.self, forKey: .totalCount, default: 0)
        hasMore = try container.decode(Bool.self, forKey: .hasMore, default: false)
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

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        roomId = try container.decode(String.self, forKey: .roomId)
        roomName = try container.decode(String.self, forKey: .roomName, default: "")
        agentId = try container.decodeIfPresent(String.self, forKey: .agentId)
        status = try container.decodeIfPresent(String.self, forKey: .status)
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt)
        sessionIds = try container.decode([String].self, forKey: .sessionIds, default: [])
        sessionCount = try container.decode(Int.self, forKey: .sessionCount, default: 0)
    }
}
