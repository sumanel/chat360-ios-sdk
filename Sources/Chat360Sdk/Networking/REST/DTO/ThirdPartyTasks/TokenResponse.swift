import Foundation

public struct TokenEnvelope: Codable {
    public var success: Bool = false
    public var data: TokenResponse?

    public init(success: Bool = false, data: TokenResponse? = nil) {
        self.success = success
        self.data = data
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
}
