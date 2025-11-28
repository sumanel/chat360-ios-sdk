import Foundation
import SwiftUI
import WebKit

@objc
@available(iOS 13.0, *)
public class Chat360Bot: NSObject {
    @objc public static let shared = Chat360Bot()

    @objc public var config: Chat360Config?
    @objc public var botController: ChatController?
    @objc var onBackClick: (() -> Void)?

    @objc public var handleWindowEvents: (([String: String]) -> [String: String])?
    @objc public var onLocationNeeded: ((String, @escaping (String, String) -> Void) -> Void)? {
        didSet {
            // If not set, use built-in location manager
            if onLocationNeeded == nil {
                setupDefaultLocationHandler()
            }
        }
    }

    @objc private var baseUrl: String?

    override init() {
        super.init()
        // Setup default location handler on init
        setupDefaultLocationHandler()
    }

    @objc public func setConfig(chat360Config: Chat360Config) {
        config = chat360Config
    }

    @objc public func setBaseUrl(url: String) {
        baseUrl = url
    }

    @objc public func getBaseUrl() -> String? {
        return baseUrl
    }

    private func setupDefaultLocationHandler() {
        // Use built-in location manager if no custom handler is set
        onLocationNeeded = { _, completion in
            Chat360LocationManager.shared.requestLocation { latitude, longitude in
                completion(String(latitude),String(longitude))
            }
        }
    }

    @objc public func sendEventToBot(event: [String: String]) {
        Chat360JSBridge.shared.send(type: "CHAT360_WINDOW_EVENT", data: event)
    }

    @objc public func initializesBotView() throws -> ChatController {
        guard let botConfig = config else {
            assertionFailure("config not found. Instead please use setConfig(config) to set the configuration then call this function.")
            throw Chat360Error.configDoesNotExit
        }
        botController = ChatController(botConfig: botConfig)
        return botController!
    }

    @objc public func startChatbot(animated: Bool = true,
                                   onBackClick: (() -> Void)? = nil,
                                   completion: (() -> Void)? = nil) throws
    {
        guard let controller = UIApplication.shared.windows.first(where: { $0.isKeyWindow })?.rootViewController else {
            NSLog("View controller not found. Instead use startChatbot(on:animated:completion) and pass view controller as a first parameter")
            return
        }
        try startChatbot(on: controller, animated: animated, onBackClick: onBackClick, completion: completion)
    }

    @objc public func startChatbot(on viewController: UIViewController,
                                   animated: Bool = true,
                                   onBackClick: (() -> Void)? = nil,
                                   completion: (() -> Void)? = nil) throws
    {
        self.onBackClick = onBackClick
        try initializesBotView()
        viewController.present(botController!, animated: animated, completion: completion)
    }

    @objc public func closeChatBot(animated _: Bool = true, completion: (() -> Void)? = nil) {
        guard let botController = botController else {
            NSLog("[Chat360SDK]: Bot is not initialized")
            return
        }

        closeChatBot(on: botController, animated: true) {
            self.onBackClick?()
            completion?()
        }
    }

    @objc public func closeChatBot(on viewController: UIViewController,
                                   animated: Bool = true,
                                   completion: (() -> Void)? = nil)
    {
        viewController.dismiss(animated: animated, completion: completion)
    }
}
