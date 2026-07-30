import Foundation

struct SessionInitResponse: Decodable {
    var id: String?
    var nodeType: String?
    var targetId: String?
    var room_id: String
    var owner_id: String
    var session_token: String?
    var session_id: String?
    // Live-chat resume state - lets a killed-and-reopened app pick up mid-live-chat state
    // correctly instead of assuming a fresh bot-flow session.
    var takeover: Bool = false
    var assigned_user: SessionAssignedUser?
    var configs: SessionConfigs?

    private enum CodingKeys: String, CodingKey {
        case id, nodeType, targetId, room_id, owner_id, session_token, session_id, takeover, assigned_user, configs
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id)
        nodeType = try c.decodeIfPresent(String.self, forKey: .nodeType)
        targetId = try c.decodeIfPresent(String.self, forKey: .targetId)
        room_id = try c.decode(String.self, forKey: .room_id)
        owner_id = try c.decode(String.self, forKey: .owner_id)
        session_token = try c.decodeIfPresent(String.self, forKey: .session_token)
        session_id = try c.decodeIfPresent(String.self, forKey: .session_id)
        takeover = try c.decodeIfPresent(Bool.self, forKey: .takeover) ?? false
        assigned_user = try c.decodeIfPresent(SessionAssignedUser.self, forKey: .assigned_user)
        configs = try c.decodeIfPresent(SessionConfigs.self, forKey: .configs)
    }
}

struct SessionAssignedUser: Decodable {
    var avatar: String?
    var user_designation: String?
    var operator_name: String?
}

struct SessionConfigs: Decodable {
    var should_ask_feedback: Bool = false

    private enum CodingKeys: String, CodingKey { case should_ask_feedback }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        should_ask_feedback = try c.decodeIfPresent(Bool.self, forKey: .should_ask_feedback) ?? false
    }
}
