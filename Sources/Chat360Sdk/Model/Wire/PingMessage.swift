import Foundation

public struct PingMessage: Codable {
    public var type: String = "ping"
    public var timestamp_int: Int64

    public init(timestamp_int: Int64) {
        self.timestamp_int = timestamp_int
    }
}
