import Foundation

/// Advances the bot flow to a target node without user input - the client sends this right after
/// connecting when session-init returns an INIT node, which is what makes the bot emit its first
/// message.
struct SystemJumpMessage: Codable {
    struct JumpData: Codable {
        var target_id: String
        var currentUrl: String
    }

    var user: String = "bot"
    var data: JumpData
    var bot_id: String
    var first_name: String = "System"
    var last_name: String = "Message"
    var curr_id: String?
    var room_id: String?
}
