import Foundation

enum Chat360ApiError: Error {
    case invalidURL(String)
    case httpError(code: Int, url: URL?)
}

/// Minimal native REST client for the Chat360 backend, used in place of the WebView.
final class Chat360ApiService {
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

    func getSession(botId: String, websiteUrl: String, currentUrl: String, standalone: Bool = true) async throws -> SessionInitResponse {
        var components = URLComponents(string: "\(trimmedBaseUrl)/api/clientwidget_updated/session/\(botId)")
        var query = [
            URLQueryItem(name: "website_url", value: websiteUrl),
            URLQueryItem(name: "location", value: ""),
            URLQueryItem(name: "region", value: ""),
            URLQueryItem(name: "country_code", value: ""),
            URLQueryItem(name: "current_url", value: currentUrl),
        ]
        if standalone { query.append(URLQueryItem(name: "standalone", value: "true")) }
        components?.queryItems = query
        guard let url = components?.url else { throw Chat360ApiError.invalidURL("session/\(botId)") }
        let data = try await execute(URLRequest(url: url))
        return try decoder.decode(SessionInitResponse.self, from: data)
    }

    /// Mirrors `getFirstMessages()`: a bare JSON array of frames (not wrapped like
    /// `HistoryResponse`), each decodable the same way history/live frames are.
    func getFirstMessages(botId: String) async throws -> [RawSocketEnvelope] {
        guard let url = URL(string: "\(trimmedBaseUrl)/api/chatbox/short-data/\(botId)") else {
            throw Chat360ApiError.invalidURL("short-data/\(botId)")
        }
        let data = try await execute(URLRequest(url: url))
        return try decoder.decode([RawSocketEnvelope].self, from: data)
    }

    /// `taskType`/`taskValue` page further back in history - pass `taskType: "PREVIOUS"` with the
    /// previous response's `previous_cursor` as `taskValue` to fetch the next older page. Omit
    /// both for the first (most recent) page.
    func getHistory(roomId: String, limit: Int = 10, taskType: String? = nil, taskValue: Int? = nil) async throws -> HistoryResponse {
        var components = URLComponents(string: "\(trimmedBaseUrl)/api/clientwidget_updated/chatbox/messages/\(roomId)")
        var query = [URLQueryItem(name: "limit", value: String(limit))]
        if let taskType { query.append(URLQueryItem(name: "task_type", value: taskType)) }
        if let taskValue { query.append(URLQueryItem(name: "task_value", value: String(taskValue))) }
        components?.queryItems = query
        guard let url = components?.url else { throw Chat360ApiError.invalidURL("chatbox/messages/\(roomId)") }
        let data = try await execute(URLRequest(url: url))
        return try decoder.decode(HistoryResponse.self, from: data)
    }

    /// Mirrors `uploadFile()`: multipart POST, response is a JSON array of URLs.
    func uploadMedia(
        roomId: String,
        botId: String,
        fileBytes: Data,
        fileName: String,
        mimeType: String,
        onProgress: @escaping (_ percent: Int) -> Void = { _ in }
    ) async throws -> [String] {
        guard let url = URL(string: "\(trimmedBaseUrl)/api/chatbox/client_media/\(roomId)") else {
            throw Chat360ApiError.invalidURL("client_media/\(roomId)")
        }
        let boundary = "Chat360Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        let body = multipartBody(boundary: boundary, fileBytes: fileBytes, fileName: fileName, mimeType: mimeType, botId: botId)

        let progressDelegate = UploadProgressDelegate(onProgress: onProgress)
        let (data, response) = try await session.upload(for: request, from: body, delegate: progressDelegate)
        try validate(response, url: url)
        return try decoder.decode([String].self, from: data)
    }

    /// The bot's server-side appearance/branding config.
    func getBotAppearance(botId: String, websiteUrl: String, subdomainUrl: String, preview: Bool = false) async throws -> BotAppearanceResponse {
        var components = URLComponents(string: "\(trimmedBaseUrl)/api/chatbox/\(botId)/chatboxappeareance")
        var query = [
            URLQueryItem(name: "website_url", value: websiteUrl),
            URLQueryItem(name: "subdomain_url", value: subdomainUrl),
        ]
        if preview { query.append(URLQueryItem(name: "preview", value: "true")) }
        components?.queryItems = query
        guard let url = components?.url else { throw Chat360ApiError.invalidURL("chatboxappeareance/\(botId)") }
        let data = try await execute(URLRequest(url: url))
        return try decoder.decode(BotAppearanceResponse.self, from: data)
    }

    private func multipartBody(boundary: String, fileBytes: Data, fileName: String, mimeType: String, botId: String) -> Data {
        var body = Data()
        body.append("--\(boundary)\r\n".utf8Data)
        body.append("Content-Disposition: form-data; name=\"media_file\"; filename=\"\(fileName)\"\r\n".utf8Data)
        body.append("Content-Type: \(mimeType)\r\n\r\n".utf8Data)
        body.append(fileBytes)
        body.append("\r\n".utf8Data)
        body.append("--\(boundary)\r\n".utf8Data)
        body.append("Content-Disposition: form-data; name=\"bot_id\"\r\n\r\n".utf8Data)
        body.append("\(botId)\r\n".utf8Data)
        body.append("--\(boundary)--\r\n".utf8Data)
        return body
    }

    private func execute(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        // TEMP diagnostic logging for the "connecting..." / Chat360ApiError RCA - remove once resolved.
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            print("[Chat360ApiService] \(http.statusCode) for \(request.url?.absoluteString ?? "?") - body: \(String(data: data, encoding: .utf8) ?? "<non-utf8>")")
        }
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

private extension String {
    var utf8Data: Data { Data(utf8) }
}

/// Reports multipart upload progress via `URLSessionTaskDelegate`, since the async
/// `session.upload(for:from:)` API has no progress callback of its own.
private final class UploadProgressDelegate: NSObject, URLSessionTaskDelegate {
    let onProgress: (Int) -> Void
    init(onProgress: @escaping (Int) -> Void) { self.onProgress = onProgress }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didSendBodyData bytesSent: Int64,
        totalBytesSent: Int64,
        totalBytesExpectedToSend: Int64
    ) {
        guard totalBytesExpectedToSend > 0 else { return }
        onProgress(Int((totalBytesSent * 100) / totalBytesExpectedToSend))
    }
}
