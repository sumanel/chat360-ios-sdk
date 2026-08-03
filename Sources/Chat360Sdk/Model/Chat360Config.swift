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

    /// Which built-in look the native chat screen starts from; `.custom` defers entirely to
    /// `customLightColors`/`customDarkColors`/`customBranding`. Not exposed to Objective-C since
    /// `Chat360ThemePreset` is a Swift-only enum.
    public var themePreset: Chat360ThemePreset = .standard
    public var customLightColors: Chat360Colors?
    public var customDarkColors: Chat360Colors?
    public var customTypography: Chat360Typography?
    public var customBranding: Chat360Branding?
    /// Host apps (or specific integrations) can turn conversation-history fetch off entirely.
    @objc public var historyEnabled: Bool = true
    /// Whether the bot proactively sends an opening message before the user says anything (a REST
    /// conversation-starter fetch, plus a WS jump to start the flow on a brand-new session). When
    /// false, a fresh session shows the welcome/logo screen instead, and the bot's flow only
    /// starts once the user sends their first message.
    @objc public var conversationStarterEnabled: Bool = true
    /// Which input bar affordances (attachment, emoji, dictation, mic) are offered - defaults to
    /// all on. Not exposed to Objective-C since `Chat360InputBarConfig` is a Swift-only struct.
    public var inputBarConfig: Chat360InputBarConfig = Chat360InputBarConfig()

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
    
    /// Same host-resolution precedence `createBaseUrl` uses for the legacy WebView URL
    /// (`Chat360Bot`'s own override, else the debug/staging split) - reused by the native chat
    /// screen so both paths agree on which server to talk to.
    var resolvedBaseUrl: String {
        Chat360Bot.shared.getBaseUrl() ?? (isDebug ? stagingUrl : baseUrl)
    }

    @objc private func createBaseUrl(with metaString: String?) -> URL? {
        let host = resolvedBaseUrl

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
