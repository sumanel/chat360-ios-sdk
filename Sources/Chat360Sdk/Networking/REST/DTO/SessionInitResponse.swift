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
    /// Kept as a raw JSON tree rather than a strictly-typed shape - the real backend's
    /// `bot_shortcuts`/`languages` sub-shapes don't reliably match a fixed Codable model (e.g. an
    /// empty map can come back as `[]` instead of `{}`), and a shape surprise in a field we barely
    /// use must never break session-init entirely. `botShortcuts`/`languages` below extract just
    /// what's needed, defensively.
    var bot_settings: JSONValue?

    private enum CodingKeys: String, CodingKey {
        case id, nodeType, targetId, room_id, owner_id, session_token, session_id, takeover, assigned_user, configs, bot_settings
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
        bot_settings = try? c.decodeIfPresent(JSONValue.self, forKey: .bot_settings)
    }
}

/// A header shortcuts-menu entry: tapping it jumps the flow straight to `targetId`.
struct SessionShortcut: Equatable, Identifiable {
    var label: String
    var targetId: String
    var id: String { label }
}

/// One entry of `bot_settings.languages` - selecting it jumps the flow to that language's entry node.
struct SessionLanguage: Equatable, Identifiable {
    var key: String
    var value: String
    var isDefault: Bool
    var id: String { key }
}

extension SessionInitResponse {
    /// `bot_settings.bot_shortcuts` is a label -> targetId map. Extracted defensively with
    /// `runCatching`-equivalent guards - a shape surprise here yields an empty list, never a crash.
    var botShortcuts: [SessionShortcut] {
        guard case .object(let dict)? = bot_settings?["bot_shortcuts"] else { return [] }
        return dict.compactMap { key, value in
            guard let targetId = value.contentOrNull, !targetId.isEmpty else { return nil }
            return SessionShortcut(label: key, targetId: targetId)
        }
    }

    var languages: [SessionLanguage] {
        guard let items = bot_settings?["languages"]?.arrayValue else { return [] }
        return items.compactMap { item in
            guard let key = item.string("key"), let value = item.string("value"), !key.isEmpty else { return nil }
            return SessionLanguage(key: key, value: value, isDefault: item.boolean("default"))
        }
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
