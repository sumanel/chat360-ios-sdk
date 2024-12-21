import Foundation

@objc public class Chat360Config : NSObject {
    @objc var baseUrl: String = "https://app.chat360.io/page?h="
    @objc private var stagingUrl = "https://staging.chat360.io/page/?h="
    @objc var botId: String? = ""
    @objc var appId: String? = ""
    @objc var isDebug: Bool = false
    @objc var flutter: Bool = false
    @objc var meta: [String: String]?
    
    @objc public init(botId: String, appId: String, deviceToken: String = "", isDebug: Bool = false, flutter: Bool = false, meta: [String: String]? = nil) {
        self.botId = botId
        self.appId = appId
        self.isDebug = isDebug
        self.flutter = flutter
        self.meta = meta
    }
    
    @objc func createUrl() -> URL? {
        do {
            // Check if meta is nil or empty
            guard let meta = meta, !meta.isEmpty else {
                return createBaseUrl(with: nil)
            }
            
            let jsonData = try JSONSerialization.data(withJSONObject: meta, options: [])
            if let jsonString = String(data: jsonData, encoding: .utf8)?.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
                return createBaseUrl(with: jsonString)
            }
        } catch {
            print("Error: \(error.localizedDescription)")
        }
        return nil  // Return a default value or handle this case accordingly
    }
    
    @objc private func createBaseUrl(with metaString: String?) -> URL? {
        let base = isDebug ? stagingUrl : baseUrl
        var urlString = "\(base)\(botId ?? "")&store_session=1&app_id=\(appId ?? "")&is_mobile=true&mobile=1"
        
        if let metaString = metaString {
            urlString += "&meta=\(metaString)"
        }
        
        if flutter {
            urlString += "&flutter_sdk_type=ios"
        }
        
        return URL(string: urlString)
    }
}
