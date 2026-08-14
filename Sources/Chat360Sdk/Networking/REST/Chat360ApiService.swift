import Foundation

@available(iOS 13.0, *)
public final class Chat360ApiService: NSObject {
    private let baseUrl: String
    private let session: URLSession
    private let decoder: JSONDecoder

    public init(baseUrl: String, session: URLSession = URLSession(configuration: .default)) {
        self.baseUrl = baseUrl
        self.session = session
        self.decoder = JSONDecoder()
        super.init()
    }

    private var trimmedBaseUrl: String {
        var url = baseUrl
        while url.hasSuffix("/") { url.removeLast() }
        return url
    }

    public func getSession(
        botId: String,
        websiteUrl: String,
        currentUrl: String,
        standalone: Bool = true,
        roomId: String? = nil,
        sessionId: String? = nil
    ) async throws -> SessionInitResponse {
        var components = URLComponents(string: "\(trimmedBaseUrl)/api/clientwidget_updated/session/\(botId)")!
        var items = [
            URLQueryItem(name: "website_url", value: websiteUrl),
            URLQueryItem(name: "location", value: ""),
            URLQueryItem(name: "region", value: ""),
            URLQueryItem(name: "country_code", value: ""),
            URLQueryItem(name: "current_url", value: currentUrl),
        ]
        if standalone { items.append(URLQueryItem(name: "standalone", value: "true")) }
        if let roomId { items.append(URLQueryItem(name: "room_id", value: roomId)) }
        if let sessionId { items.append(URLQueryItem(name: "session_id", value: sessionId)) }
        components.queryItems = items

        let request = URLRequest(url: components.url!)
        let data = try await execute(request)
        return try decoder.decode(SessionInitResponse.self, from: data)
    }

    public func getFirstMessages(botId: String) async throws -> [RawSocketEnvelope] {
        let url = URL(string: "\(trimmedBaseUrl)/api/chatbox/short-data/\(botId)")!
        let data = try await execute(URLRequest(url: url))
        return try decoder.decode([RawSocketEnvelope].self, from: data)
    }

    public func getHistory(roomId: String, limit: Int = 10, taskType: String? = nil, taskValue: Int? = nil) async throws -> HistoryResponse {
        var components = URLComponents(string: "\(trimmedBaseUrl)/api/clientwidget_updated/chatbox/messages/\(roomId)")!
        var items = [URLQueryItem(name: "limit", value: String(limit))]
        if let taskType { items.append(URLQueryItem(name: "task_type", value: taskType)) }
        if let taskValue { items.append(URLQueryItem(name: "task_value", value: String(taskValue))) }
        components.queryItems = items

        let data = try await execute(URLRequest(url: components.url!))
        return try decoder.decode(HistoryResponse.self, from: data)
    }

    public func uploadMedia(
        roomId: String,
        botId: String,
        fileBytes: Data,
        fileName: String,
        mimeType: String,
        onProgress: @escaping (Int) -> Void = { _ in }
    ) async throws -> [String] {
        let boundary = "Chat360Boundary-\(UUID().uuidString)"
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"media_file\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(fileBytes)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"bot_id\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(botId)\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        let url = URL(string: "\(trimmedBaseUrl)/api/chatbox/client_media/\(roomId)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let data = try await executeUpload(request, body: body, onProgress: onProgress)
        return try decoder.decode([String].self, from: data)
    }

    public func getBotAppearance(
        botId: String,
        websiteUrl: String,
        subdomainUrl: String,
        preview: Bool = false
    ) async throws -> BotAppearanceResponse {
        var components = URLComponents(string: "\(trimmedBaseUrl)/api/chatbox/\(botId)/chatboxappeareance")!
        var items = [
            URLQueryItem(name: "website_url", value: websiteUrl),
            URLQueryItem(name: "subdomain_url", value: subdomainUrl),
        ]
        if preview { items.append(URLQueryItem(name: "preview", value: "true")) }
        components.queryItems = items

        let data = try await execute(URLRequest(url: components.url!))
        return try decoder.decode(BotAppearanceResponse.self, from: data)
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
                    continuation.resume(throwing: NSError(
                        domain: "Chat360SDK",
                        code: code,
                        userInfo: [NSLocalizedDescriptionKey: "HTTP \(code) for \(request.url?.absoluteString ?? "")"]
                    ))
                    return
                }
                continuation.resume(returning: data ?? Data())
            }
            task.resume()
        }
    }

    private func executeUpload(_ request: URLRequest, body: Data, onProgress: @escaping (Int) -> Void) async throws -> Data {
        let delegate = UploadProgressDelegate(onProgress: onProgress)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            delegate.onComplete = { data, response, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                    let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                    continuation.resume(throwing: NSError(
                        domain: "Chat360SDK",
                        code: code,
                        userInfo: [NSLocalizedDescriptionKey: "HTTP \(code) for \(request.url?.absoluteString ?? "")"]
                    ))
                    return
                }
                delegate.resultData = data
                continuation.resume(returning: ())
            }
            let uploadSession = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
            let task = uploadSession.uploadTask(with: request, from: body)
            delegate.task = task
            task.resume()
        }
        return delegate.resultData ?? Data()
    }
}

private final class UploadProgressDelegate: NSObject, URLSessionDataDelegate {
    let onProgress: (Int) -> Void
    var onComplete: ((Data?, URLResponse?, Error?) -> Void)?
    var task: URLSessionTask?
    var resultData: Data?
    private var receivedData = Data()
    private var response: URLResponse?

    init(onProgress: @escaping (Int) -> Void) {
        self.onProgress = onProgress
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        guard totalBytesExpectedToSend > 0 else { return }
        onProgress(Int((totalBytesSent * 100) / totalBytesExpectedToSend))
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        receivedData.append(data)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        self.response = response
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        onComplete?(receivedData, response, error)
    }
}
