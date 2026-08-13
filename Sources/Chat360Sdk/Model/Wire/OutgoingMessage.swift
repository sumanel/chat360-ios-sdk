import Foundation

public struct OutgoingMessage: Codable {
    public var type: String = "message"
    public var isLive: Bool = false
    public var replyType: String = "free_text"
    public var user: String = "end_user"
    public var userType: String = "end_user"
    public var first_name: String = "Anonymous"
    public var last_name: String = "User"
    public var message: JSONValue
    public var bot_id: String
    public var targetId: String?
    public var chat_msg_id: String = UUID().uuidString
    public var room_id: String?
    public var currentId: String?
    public var nodeType: String?
    public var post_data: JSONValue?
    public var variables: [String: String]?
    public var shouldValidate: Bool?
    public var doNotUpdateVariable: Bool?
    public var multiple_vars: Bool?
    public var componentSpecificData: JSONValue?

    public init(
        type: String = "message",
        isLive: Bool = false,
        replyType: String = "free_text",
        user: String = "end_user",
        userType: String = "end_user",
        first_name: String = "Anonymous",
        last_name: String = "User",
        message: JSONValue,
        bot_id: String,
        targetId: String?,
        chat_msg_id: String = UUID().uuidString,
        room_id: String? = nil,
        currentId: String? = nil,
        nodeType: String? = nil,
        post_data: JSONValue? = nil,
        variables: [String: String]? = nil,
        shouldValidate: Bool? = nil,
        doNotUpdateVariable: Bool? = nil,
        multiple_vars: Bool? = nil,
        componentSpecificData: JSONValue? = nil
    ) {
        self.type = type
        self.isLive = isLive
        self.replyType = replyType
        self.user = user
        self.userType = userType
        self.first_name = first_name
        self.last_name = last_name
        self.message = message
        self.bot_id = bot_id
        self.targetId = targetId
        self.chat_msg_id = chat_msg_id
        self.room_id = room_id
        self.currentId = currentId
        self.nodeType = nodeType
        self.post_data = post_data
        self.variables = variables
        self.shouldValidate = shouldValidate
        self.doNotUpdateVariable = doNotUpdateVariable
        self.multiple_vars = multiple_vars
        self.componentSpecificData = componentSpecificData
    }

    public static func freeText(botId: String, targetId: String?, roomId: String?, text: String) -> OutgoingMessage {
        OutgoingMessage(message: .string(text), bot_id: botId, targetId: targetId, room_id: roomId)
    }
}
