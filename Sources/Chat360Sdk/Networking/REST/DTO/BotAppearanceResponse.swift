import Foundation

/// `json_info` arrives as a JSON-*encoded string* inside the outer object, not a nested object -
/// decode it separately once this outer shape is parsed (see `details(decoder:)` below).
struct BotAppearanceResponse: Decodable {
    var chatboxname: String?
    var json_info: String?
}

/// Only the subset of json_info's tokens this rewrite currently maps to Chat360 colors/branding.
struct BotAppearanceDetails: Decodable {
    struct ChatboxHeader: Decodable {
        var primarychatboxHeaderColor: String?
        var secondaryChatboxHeaderColor: String?
        var chatboxAvatar: String?
    }

    var botBackgroundColor: String?
    var primaryBackgroundColor: String?
    var botMessageBoxColor: String?
    var userMessageBoxColor: String?
    var botTextColor: String?
    var userTextColor: String?
    var buttonColor: String?
    var buttonTxtColor: String?
    var statusColor: String?
    var chatboxHeader: ChatboxHeader?
    /// The bot-owner-authored post-chat survey definition.
    var feedback_config: FeedbackConfig?
}

extension BotAppearanceResponse {
    /// Decodes `json_info`, tolerating a malformed/missing blob (returns nil) rather than failing the fetch.
    func details(using decoder: JSONDecoder = JSONDecoder()) -> BotAppearanceDetails? {
        guard let raw = json_info, let data = raw.data(using: .utf8) else { return nil }
        return try? decoder.decode(BotAppearanceDetails.self, from: data)
    }
}
