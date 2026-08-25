import Foundation

@available(iOS 13.0, *)
public final class ThirdPartyTasksApiService {
    private let baseUrl: String
    private let session: URLSession
    private let decoder: JSONDecoder

    public init(baseUrl: String, session: URLSession = URLSession(configuration: .default)) {
        self.baseUrl = baseUrl
        self.session = session
        self.decoder = JSONDecoder()
    }

    private var trimmedBaseUrl: String {
        var url = baseUrl
        while url.hasSuffix("/") { url.removeLast() }
        return url
    }

    public func fetchToken(clientId: String, apiKey: String) async throws -> TokenResponse {
        let url = URL(string: "\(trimmedBaseUrl)/api/third-party-tasks/auth/token")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["client_id": clientId])

        let data = try await execute(request)
        guard let value = try decoder.decode(TokenEnvelope.self, from: data).data else {
            throw ThirdPartyMalformedResponseException(endpoint: "auth/token")
        }
        return value
    }

    public func fetchRoomsList(
        clientId: String,
        bearerToken: String,
        agentId: String,
        limit: Int? = nil,
        offset: Int? = nil
    ) async throws -> RoomsListResponse {
        var components = URLComponents(string: "\(trimmedBaseUrl)/api/third-party-tasks/rooms/list")!
        var items = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "agent_id", value: agentId),
        ]
        if let limit { items.append(URLQueryItem(name: "limit", value: String(limit))) }
        if let offset { items.append(URLQueryItem(name: "offset", value: String(offset))) }
        components.queryItems = items

        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")

        let data = try await execute(request)
        guard let value = try decoder.decode(RoomsListEnvelope.self, from: data).data else {
            throw ThirdPartyMalformedResponseException(endpoint: "rooms/list")
        }
        return value
    }

    public func updateRoom(roomId: String, clientId: String, roomName: String, bearerToken: String) async throws -> RoomUpdateResponse {
        let url = URL(string: "\(trimmedBaseUrl)/api/third-party-tasks/room/update")!
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
        guard let value = try decoder.decode(RoomUpdateEnvelope.self, from: data).data else {
            throw ThirdPartyMalformedResponseException(endpoint: "room/update")
        }
        return value
    }

    public func updateRoomStatus(roomId: String, clientId: String, bearerToken: String) async throws -> RoomStatusResponse {
        let url = URL(string: "\(trimmedBaseUrl)/api/third-party-tasks/room/update/status")!
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "room_id": roomId,
            "client_id": clientId,
        ])

        let data = try await execute(request)
        guard let value = try decoder.decode(RoomStatusEnvelope.self, from: data).data else {
            throw ThirdPartyMalformedResponseException(endpoint: "room/update/status")
        }
        return value
    }

    public func submitFeedback(
        roomId: String, sessionId: String, messageId: String, query: String, response: String,
        feedback: String, remarks: String?, bearerToken: String
    ) async throws {
        let url = URL(string: "\(trimmedBaseUrl)/api/third-party-tasks/feedback/queries")!
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        let data: [String: Any] = [
            "message_id": messageId,
            "query": query,
            "response": response,
            "feedback": feedback,
            "Remarks": remarks ?? NSNull(),
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "room_id": roomId,
            "session_id": sessionId,
            "data": data,
        ] as [String: Any])
        _ = try await execute(request)
    }

    // A separate, lighter-weight feedback surface from `submitFeedback` above (message-specific
    // like/dislike) - this is a periodic "how's the conversation going" prompt, so it only ever
    // carries free text, no message/query/response context.
    public func submitPeriodicFeedback(roomId: String, sessionId: String, feedbackText: String, bearerToken: String) async throws {
        let url = URL(string: "\(trimmedBaseUrl)/api/third-party-tasks/feedback")!
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        let body: [String: Any] = [
            "room_id": roomId,
            "session_id": sessionId,
            "data": ["feedback": feedbackText],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        NSLog("[Chat360] >> PATCH %@ body=%@", url.absoluteString, body)
        _ = try await execute(request)
        NSLog("[Chat360] << PATCH %@ succeeded (2xx)", url.absoluteString)
    }

    private func execute(_ request: URLRequest) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            let task = session.dataTask(with: request) { data, response, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                    let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                    continuation.resume(throwing: ThirdPartyHttpException(httpCode: code, url: request.url?.absoluteString ?? ""))
                    return
                }
                continuation.resume(returning: data ?? Data())
            }
            task.resume()
        }
    }
}
