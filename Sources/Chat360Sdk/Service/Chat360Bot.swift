import Foundation
import SwiftUI

@objc
@available(iOS 13.0, *)
public class Chat360Bot: NSObject {
    @objc public static let shared = Chat360Bot()
    
    @objc public var config: Chat360Config? = nil
    
    @objc public var botController : ChatController?
    
    @objc public func setConfig(chat360Config: Chat360Config) {
        config = chat360Config
    }
    
    @objc public func initializesBotView() throws -> ChatController {
        guard let botConfig = config else {
            assertionFailure("config not found. Instead please use setConfig(config) to set the configuration then call this function.")
            throw Chat360Error.configDoesNotExit
        }
        self.botController = ChatController(botConfig: botConfig)
        return botController!;
    }
    
    @objc public func startChatbot(animated: Bool = true, completion: (() -> Void)? = nil) throws {
           guard let controller = UIApplication.shared.windows.first(where: {$0.isKeyWindow})?.rootViewController else {
               NSLog("View controller not found. Instead use startChatbot(on:animated:completion) and pass view controller as a first parameter")
               return
           }
           try startChatbot(on: controller, animated: animated, completion: completion)
       }
    
    
    @objc public func startChatbot(on viewController: UIViewController, animated: Bool = true, completion: (() -> Void)? = nil) throws {
        try initializesBotView()
        viewController.present(self.botController!, animated: animated, completion: completion)
    }
    

    @objc public func closeChatBot(animated: Bool = true, completion: (() -> Void)? = nil) {
        guard let botController = self.botController else {
            NSLog("[Chat360SDK]: Bot is not initialized")
            return
        }
        closeChatBot(on: botController, animated: true, completion: completion)
    }

    
    @objc public func closeChatBot(on viewController: UIViewController, animated: Bool = true, completion: (() -> Void)? = nil) {
        viewController.dismiss(animated: animated, completion: completion)
    }
    
}
