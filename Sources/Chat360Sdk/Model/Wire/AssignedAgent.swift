import Foundation

/// A human agent assigned to the session (ports the `highlight` node's `assigned_user`).
public struct AssignedAgent: Equatable {
    public var name: String?
    public var designation: String?
    public var avatarUrl: String?

    public init(name: String?, designation: String?, avatarUrl: String?) {
        self.name = name
        self.designation = designation
        self.avatarUrl = avatarUrl
    }
}
