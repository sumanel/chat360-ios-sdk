import Foundation

@objc
@available(iOS 13.0, *)
public class Chat360Config : NSObject {
    @objc var baseUrl: String = "https://app.chat360.io"
    @objc private var stagingUrl = "https://staging.chat360.io"
    
    @objc var botId: String? = ""
    @objc var appId: String? = ""
    @objc var isDebug: Bool = false
    @objc var flutter: Bool = false
    @objc var meta: [String: String]?
    
    @objc var useNewUI: Bool = false
    
    @objc public init(botId: String,
                      appId: String,
                      isDebug: Bool = false,
                      flutter: Bool = false,
                      meta: [String: String]? = nil,
                      useNewUI: Bool = false) {
        self.botId = botId
        self.appId = appId
        self.isDebug = isDebug
        self.flutter = flutter
        self.meta = meta
        self.useNewUI = useNewUI
    }
    
    
    @objc func createUrl() -> URL? {
        do {
            guard let meta = meta, !meta.isEmpty else {
                return createBaseUrl(with: nil)
            }
            
            let jsonData = try JSONSerialization.data(withJSONObject: meta, options: [])
            if let jsonString = String(data: jsonData, encoding: .utf8)?
                .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
                return createBaseUrl(with: jsonString)
            }
        } catch {
            print("Error: \(error.localizedDescription)")
        }
        return createBaseUrl(with: nil)
    }
    
    @objc private func createBaseUrl(with metaString: String?) -> URL? {
        let host = Chat360Bot.shared.getBaseUrl() ?? (isDebug ? stagingUrl : baseUrl)
        
        let path = useNewUI ? "/web_bot?h=" : "/page?h="
        
        guard let botId = botId, let appId = appId else { return nil }
        
        var urlString = "\(host)\(path)\(botId)&store_session=1&app_id=\(appId)&is_mobile=true&mobile=1"
        
        if let metaString = metaString {
            urlString += "&meta=\(metaString)"
        }
        
        if flutter {
            urlString += "&flutter_sdk_type=ios"
        }
        
        return URL(string: urlString)
    }
}
