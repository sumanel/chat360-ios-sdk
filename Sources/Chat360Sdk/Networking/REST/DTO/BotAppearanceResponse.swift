import Foundation

public struct BotAppearanceResponse: Codable {
    public var chatboxname: String?
    public var json_info: String?

    public init(chatboxname: String? = nil, json_info: String? = nil) {
        self.chatboxname = chatboxname
        self.json_info = json_info
    }
}

public struct BotAppearanceDetails: Codable {
    public struct ChatboxHeader: Codable {
        public var primarychatboxHeaderColor: String?
        public var secondaryChatboxHeaderColor: String?
        public var chatboxAvatar: String?

        public init(primarychatboxHeaderColor: String? = nil, secondaryChatboxHeaderColor: String? = nil, chatboxAvatar: String? = nil) {
            self.primarychatboxHeaderColor = primarychatboxHeaderColor
            self.secondaryChatboxHeaderColor = secondaryChatboxHeaderColor
            self.chatboxAvatar = chatboxAvatar
        }
    }

    public var botBackgroundColor: String?
    public var primaryBackgroundColor: String?
    public var botMessageBoxColor: String?
    public var userMessageBoxColor: String?
    public var botTextColor: String?
    public var userTextColor: String?
    public var buttonColor: String?
    public var buttonTxtColor: String?
    public var statusColor: String?
    public var chatboxHeader: ChatboxHeader?
    public var feedback_config: FeedbackConfig?

    public init(
        botBackgroundColor: String? = nil, primaryBackgroundColor: String? = nil, botMessageBoxColor: String? = nil,
        userMessageBoxColor: String? = nil, botTextColor: String? = nil, userTextColor: String? = nil,
        buttonColor: String? = nil, buttonTxtColor: String? = nil, statusColor: String? = nil,
        chatboxHeader: ChatboxHeader? = nil, feedback_config: FeedbackConfig? = nil
    ) {
        self.botBackgroundColor = botBackgroundColor
        self.primaryBackgroundColor = primaryBackgroundColor
        self.botMessageBoxColor = botMessageBoxColor
        self.userMessageBoxColor = userMessageBoxColor
        self.botTextColor = botTextColor
        self.userTextColor = userTextColor
        self.buttonColor = buttonColor
        self.buttonTxtColor = buttonTxtColor
        self.statusColor = statusColor
        self.chatboxHeader = chatboxHeader
        self.feedback_config = feedback_config
    }
}

extension BotAppearanceResponse {
    public func details(decoder: JSONDecoder = JSONDecoder()) -> BotAppearanceDetails? {
        guard let raw = json_info, let data = raw.data(using: .utf8) else { return nil }
        return try? decoder.decode(BotAppearanceDetails.self, from: data)
    }
}
