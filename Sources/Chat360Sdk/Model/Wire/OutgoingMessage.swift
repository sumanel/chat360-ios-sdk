import Foundation

/// Wire shape for a client -> server chat message. `message` is a `JSONValue` because the backend
/// accepts either a plain string (free text) or a typed object (quick-reply selection, file
/// upload, location, etc.) depending on `replyType`/`msgType`.
///
/// Field names deliberately mix snake_case and camelCase to match the exact wire format the
/// backend expects - do not "clean up" the naming, it isn't a Swift style choice.
struct OutgoingMessage: Encodable {
    var type: String = "message"
    var isLive: Bool = false
    var replyType: String = "free_text"
    var user: String = "end_user"
    var userType: String = "end_user"
    var first_name: String = "Anonymous"
    var last_name: String = "User"
    var message: JSONValue
    var bot_id: String
    var targetId: String?
    var chat_msg_id: String = UUID().uuidString
    var room_id: String?
    var currentId: String?
    var nodeType: String?
    var post_data: JSONValue?
    var variables: [String: String]?
    var shouldValidate: Bool?
    var doNotUpdateVariable: Bool?
    var multiple_vars: Bool?
    /// An opaque per-message-type payload (e.g. VOICE_MESSAGE's {voiceUrl, transcript, msgType}).
    var componentSpecificData: JSONValue?

    static func freeText(botId: String, targetId: String?, roomId: String?, text: String) -> OutgoingMessage {
        OutgoingMessage(message: .string(text), bot_id: botId, targetId: targetId, room_id: roomId)
    }
}
