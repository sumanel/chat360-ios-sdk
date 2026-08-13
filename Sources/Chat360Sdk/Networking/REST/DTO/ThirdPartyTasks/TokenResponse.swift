import Foundation

public struct TokenEnvelope: Codable {
    public var success: Bool = false
    public var data: TokenResponse?

    public init(success: Bool = false, data: TokenResponse? = nil) {
        self.success = success
        self.data = data
    }

    enum CodingKeys: String, CodingKey {
        case success, data
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        success = try container.decode(Bool.self, forKey: .success, default: false)
        data = try container.decodeIfPresent(TokenResponse.self, forKey: .data)
    }
}

public struct TokenResponse: Codable {
    public var bearerToken: String
    public var tokenType: String = "Bearer"
    public var expiresIn: Int64 = 3600

    enum CodingKeys: String, CodingKey {
        case bearerToken = "bearer_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
    }

    public init(bearerToken: String, tokenType: String = "Bearer", expiresIn: Int64 = 3600) {
        self.bearerToken = bearerToken
        self.tokenType = tokenType
        self.expiresIn = expiresIn
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        bearerToken = try container.decode(String.self, forKey: .bearerToken)
        tokenType = try container.decode(String.self, forKey: .tokenType, default: "Bearer")
        expiresIn = try container.decode(Int64.self, forKey: .expiresIn, default: 3600)
    }
}
