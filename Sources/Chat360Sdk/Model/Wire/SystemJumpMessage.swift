import Foundation

public struct SystemJumpMessage: Codable {
    public struct JumpData: Codable {
        public var target_id: String
        public var currentUrl: String

        public init(target_id: String, currentUrl: String) {
            self.target_id = target_id
            self.currentUrl = currentUrl
        }
    }

    public var user: String = "bot"
    public var data: JumpData
    public var bot_id: String
    public var first_name: String = "System"
    public var last_name: String = "Message"
    public var curr_id: String?
    public var room_id: String?
    public var variable_values: [String: String]?

    public init(
        user: String = "bot",
        data: JumpData,
        bot_id: String,
        first_name: String = "System",
        last_name: String = "Message",
        curr_id: String? = nil,
        room_id: String? = nil,
        variable_values: [String: String]? = nil
    ) {
        self.user = user
        self.data = data
        self.bot_id = bot_id
        self.first_name = first_name
        self.last_name = last_name
        self.curr_id = curr_id
        self.room_id = room_id
        self.variable_values = variable_values
    }
}
