import Foundation

public struct SessionInitResponse: Codable {
    public var id: String?
    public var nodeType: String?
    public var targetId: String?
    public var room_id: String
    public var owner_id: String
    public var session_token: String?
    public var session_id: String?
    public var takeover: Bool = false
    public var assigned_user: SessionAssignedUser?
    public var configs: SessionConfigs?
    public var bot_settings: JSONValue?

    public init(
        id: String? = nil, nodeType: String? = nil, targetId: String? = nil, room_id: String, owner_id: String,
        session_token: String? = nil, session_id: String? = nil, takeover: Bool = false,
        assigned_user: SessionAssignedUser? = nil, configs: SessionConfigs? = nil, bot_settings: JSONValue? = nil
    ) {
        self.id = id; self.nodeType = nodeType; self.targetId = targetId; self.room_id = room_id
        self.owner_id = owner_id; self.session_token = session_token; self.session_id = session_id
        self.takeover = takeover; self.assigned_user = assigned_user; self.configs = configs
        self.bot_settings = bot_settings
    }
}

public struct SessionLanguage: Codable {
    public var key: String
    public var value: String
    public var `default`: Bool = false

    public init(key: String, value: String, default: Bool = false) {
        self.key = key; self.value = value; self.default = `default`
    }
}

public struct SessionAssignedUser: Codable {
    public var avatar: String?
    public var user_designation: String?
    public var operator_name: String?

    public init(avatar: String? = nil, user_designation: String? = nil, operator_name: String? = nil) {
        self.avatar = avatar; self.user_designation = user_designation; self.operator_name = operator_name
    }
}

public struct SessionConfigs: Codable {
    public var should_ask_feedback: Bool = false

    public init(should_ask_feedback: Bool = false) {
        self.should_ask_feedback = should_ask_feedback
    }
}
