import Foundation

public struct MaintenanceStatusResponse: Codable {
    public var isActive: Bool = false
    public var activatedOn: String?
    public var deactivatedOn: String?
    public var activatedBy: String?
    public var message: String = ""

    enum CodingKeys: String, CodingKey {
        case isActive = "is_active"
        case activatedOn = "activated_on"
        case deactivatedOn = "deactivated_on"
        case activatedBy = "activated_by"
        case message
    }

    public init(isActive: Bool = false, activatedOn: String? = nil, deactivatedOn: String? = nil, activatedBy: String? = nil, message: String = "") {
        self.isActive = isActive
        self.activatedOn = activatedOn
        self.deactivatedOn = deactivatedOn
        self.activatedBy = activatedBy
        self.message = message
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isActive = try container.decode(Bool.self, forKey: .isActive, default: false)
        activatedOn = try container.decodeIfPresent(String.self, forKey: .activatedOn)
        deactivatedOn = try container.decodeIfPresent(String.self, forKey: .deactivatedOn)
        activatedBy = try container.decodeIfPresent(String.self, forKey: .activatedBy)
        message = try container.decode(String.self, forKey: .message, default: "")
    }
}
