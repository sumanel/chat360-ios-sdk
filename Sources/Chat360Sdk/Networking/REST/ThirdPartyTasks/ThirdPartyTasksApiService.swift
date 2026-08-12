import Foundation

/// `URLSession`-based REST client for the `third-party-tasks` API family that backs the SDK's
/// rooms/history list.
final class ThirdPartyTasksApiService {
    private let baseUrl: String
    private let session: URLSession
    private let decoder = JSONDecoder()

    init(baseUrl: String, session: URLSession = .shared) {
        self.baseUrl = baseUrl
        self.session = session
    }

    private var trimmedBaseUrl: String {
        var trimmed = baseUrl
        while trimmed.hasSuffix("/") { trimmed.removeLast() }
        return trimmed
    }

    func fetchToken(clientId: String, apiKey: String) async throws -> TokenResponse {
        guard let url = URL(string: "\(trimmedBaseUrl)/api/third-party-tasks/auth/token") else {
            throw Chat360ApiError.invalidURL("third-party-tasks/auth/token")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["client_id": clientId])
        let data = try await execute(request)
        guard let response = try decoder.decode(TokenEnvelope.self, from: data).data else {
            throw Chat360ApiError.malformedResponse(endpoint: "auth/token")
        }
        return response
    }

    /// `clientId`, `botId`, and `agentId` must all be non-empty - there is no partial/best-effort
    /// mode for identifying who the rooms belong to.
    func fetchRoomsList(
        clientId: String,
        bearerToken: String,
        botId: String,
        agentId: String,
        limit: Int? = nil,
        offset: Int? = nil
    ) async throws -> RoomsListResponse {
        var components = URLComponents(string: "\(trimmedBaseUrl)/api/third-party-tasks/rooms/list")
        var query = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "bot_id", value: botId),
            URLQueryItem(name: "agent_id", value: agentId),
        ]
        if let limit { query.append(URLQueryItem(name: "limit", value: String(limit))) }
        if let offset { query.append(URLQueryItem(name: "offset", value: String(offset))) }
        components?.queryItems = query
        guard let url = components?.url else { throw Chat360ApiError.invalidURL("third-party-tasks/rooms/list") }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        let data = try await execute(request)
        guard let response = try decoder.decode(RoomsListEnvelope.self, from: data).data else {
            throw Chat360ApiError.malformedResponse(endpoint: "rooms/list")
        }
        return response
    }

    func updateRoom(roomId: String, clientId: String, roomName: String, bearerToken: String) async throws -> RoomUpdateResponse {
        guard let url = URL(string: "\(trimmedBaseUrl)/api/third-party-tasks/room/update") else {
            throw Chat360ApiError.invalidURL("third-party-tasks/room/update")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "room_id": roomId,
            "client_id": clientId,
            "room_name": roomName,
        ])
        let data = try await execute(request)
        guard let response = try decoder.decode(RoomUpdateEnvelope.self, from: data).data else {
            throw Chat360ApiError.malformedResponse(endpoint: "room/update")
        }
        return response
    }

    func updateRoomStatus(roomId: String, clientId: String, bearerToken: String) async throws -> RoomStatusResponse {
        guard let url = URL(string: "\(trimmedBaseUrl)/api/third-party-tasks/room/update/status") else {
            throw Chat360ApiError.invalidURL("third-party-tasks/room/update/status")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "room_id": roomId,
            "client_id": clientId,
            "status": "inactive",
        ])
        let data = try await execute(request)
        guard let response = try decoder.decode(RoomStatusEnvelope.self, from: data).data else {
            throw Chat360ApiError.malformedResponse(endpoint: "room/update/status")
        }
        return response
    }

    private func execute(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        try validate(response, url: request.url)
        return data
    }

    private func validate(_ response: URLResponse, url: URL?) throws {
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw Chat360ApiError.httpError(code: code, url: url)
        }
    }
}
