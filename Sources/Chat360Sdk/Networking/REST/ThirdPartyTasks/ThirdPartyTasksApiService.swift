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

    /// `GET third-party-tasks/welcome-text`, identified by a `Client-Id` header (no bearer token). The hyphenated spelling is the one the server
    /// reads - `client_id` with an underscore is rejected with a 400, so the request would silently fall back
    /// to the defaults. Returns the
    /// configured heading/text, or nil when neither is set. Accepts the fields at the top level, in a
    /// `data` object, or in a `data` list of such objects. Throws
    /// on any non-2xx (a 404 while the endpoint isn't deployed) or an unreadable body - the caller treats
    /// every failure the same way, by keeping what it already has.
    public func fetchWelcomeText(clientId: String) async throws -> WelcomeText? {
        var request = URLRequest(url: URL(string: "\(trimmedBaseUrl)/api/third-party-tasks/welcome-text")!)
        request.setValue(clientId, forHTTPHeaderField: "Client-Id")
        let data = try await execute(request)
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw ThirdPartyMalformedResponseException(endpoint: "welcome-text")
        }
        // `data` is either the welcome object itself or a list of them (an empty list when nothing is set).
        // Fields at the top level also work. With a list, the first entry that actually has a heading or text wins.
        let candidates: [[String: Any]]
        if let object = root["data"] as? [String: Any] {
            candidates = [object]
        } else if let list = root["data"] as? [Any] {
            candidates = list.compactMap { $0 as? [String: Any] }
        } else {
            candidates = [root]
        }
        for entry in candidates {
            func field(_ name: String) -> String? {
                (entry[name] as? String).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.flatMap { $0.isEmpty ? nil : $0 }
            }
            let value = WelcomeText(heading: field("heading"), text: field("text"))
            if !value.isEmpty { return value }
        }
        return nil
    }

    /// `POST third-party-tasks/sales-exectives` (the misspelling is the server's real route), identified by a
    /// `Client-Id` header. `details` goes out as the JSON body exactly as given. It must be sent as
    /// `application/json` - without that content type the server ignores the body and answers that both
    /// `dealer_code` and `emp_code` are required.
    ///
    /// Throws on any non-2xx (the server answers 400 with `{"success":false,...}` for validation errors and an
    /// unconfigured client) or an unreadable body; `SalesExecutiveGate` treats every failure as "let them through".
    public func checkSalesExecutive(clientId: String, details: [String: String], timeout: TimeInterval = 10) async throws -> SalesExecutiveResult {
        var request = URLRequest(url: URL(string: "\(trimmedBaseUrl)/api/third-party-tasks/sales-exectives")!)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue(clientId, forHTTPHeaderField: "Client-Id")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: details)
        let data = try await execute(request)
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw ThirdPartyMalformedResponseException(endpoint: "sales-exectives")
        }
        let executive = root["sales_executive"] as? [String: Any]
        return SalesExecutiveResult(
            success: (root["success"] as? Bool) ?? false,
            message: root["message"] as? String,
            status: executive?["status"] as? String
        )
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

    public func fetchMaintenanceStatus() async throws -> MaintenanceStatusResponse {
        let url = URL(string: "\(trimmedBaseUrl)/api/third-party-tasks/maintainance")!
        let data = try await execute(URLRequest(url: url))
        return try decoder.decode(MaintenanceStatusResponse.self, from: data)
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
