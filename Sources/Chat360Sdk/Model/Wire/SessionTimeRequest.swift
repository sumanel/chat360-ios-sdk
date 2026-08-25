import Foundation

// Asks the server for Hyundai's own session-time tracking, separate from the SDK's own
// client-side countdown - see `ChatRepository.openSocket()` for where this is sent, and
// `ChatRepository.handleIncoming(_:)` for where the response gets logged.
public struct SessionTimeRequest: Codable {
    public var data_type: String = "session_time_hyundai"
    public var room_id: String

    public init(room_id: String) {
        self.room_id = room_id
    }
}
