import Foundation

public struct AssignedAgent: Equatable {
    public let name: String?
    public let designation: String?
    public let avatarUrl: String?

    public init(name: String?, designation: String?, avatarUrl: String?) {
        self.name = name
        self.designation = designation
        self.avatarUrl = avatarUrl
    }
}
