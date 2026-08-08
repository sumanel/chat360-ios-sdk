import Foundation

struct TokenEnvelope: Decodable {
    var success: Bool = false
    var data: TokenResponse?
}

struct TokenResponse: Decodable {
    var bearer_token: String
    var token_type: String = "Bearer"
    var expires_in: Int = 3600
}
