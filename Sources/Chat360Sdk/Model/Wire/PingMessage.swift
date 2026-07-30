import Foundation

struct PingMessage: Codable {
    var type: String = "ping"
    var timestamp_int: Int64
}
