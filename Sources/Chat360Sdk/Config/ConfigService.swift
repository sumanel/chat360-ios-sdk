import Foundation

@available(iOS 13.0, *)
public final class ConfigService {
    public enum WebEventHandler {
        public static var handleWindowEvent: (([String: String]) -> [String: String])?
        public static var sendEventToBot: (([String: String]) -> Void)? = { event in
            WindowEventBridge.shared.sendToActiveSession(event)
        }
    }

    private static var instance: ConfigService?

    public static func getInstance() -> ConfigService {
        if let instance { return instance }
        let created = ConfigService()
        instance = created
        return created
    }

    private var config: CoreConfigs
    private var baseUrl: String?

    private init() {
        config = CoreConfigs(botId: "", flutter: false, meta: nil, isDebug: false, useNewUI: false)
    }

    @discardableResult
    public func setConfigData(_ config: CoreConfigs) -> Bool {
        self.config = config
        return true
    }

    public func getConfig() -> CoreConfigs {
        config
    }

    public func setBaseUrl(_ url: String) {
        baseUrl = url
    }

    public func getBaseUrl() -> String? {
        baseUrl
    }
}
