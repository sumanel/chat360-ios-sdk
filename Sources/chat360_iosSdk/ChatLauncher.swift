import Foundation
import UIKit

public class ChatLauncher{
    public static func showChat(with config: ChatConfigs, parentController: UIViewController){
        let chatVC = ChatWebViewController.init(nibName: "ChatWebViewController", bundle: nil)
        chatVC.modalPresentationStyle = .fullScreen
        chatVC.config = config
        let navigationController = UINavigationController(rootViewController: chatVC)
                parentController.present(navigationController, animated: true, completion: nil)
//        parentController.present(chatVC, animated: true) {
//
//        }
    }
}

public struct ChatConfigs {
    var baseUrl: String = "https://app.chat360.io/page?h="
    private var stagingUrl = "https://app.gaadibaazar.in/page?h="
    var botId: String? = ""
    var appId: String? = ""
    var isDebug: Bool = false
    var flutter: Bool = false
    var meta: [String: Any]?

    public init(botId: String, appId: String, deviceToken: String = "", isDebug: Bool = false, flutter: Bool = false, meta: [String: Any]? = nil) {
        self.botId = botId
        self.appId = appId
        self.isDebug = isDebug
        self.flutter = flutter
        self.meta = meta
    }

    func createUrl() -> String {
        if let metaData = meta {
            do {
                let jsonData = try JSONSerialization.data(withJSONObject: metaData, options: [])
                if let jsonString = String(data: jsonData, encoding: .utf8)?.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
                    let base = isDebug ? stagingUrl : baseUrl
                    var urlString = "\(base)\(botId ?? "")&store_session=1&app_id=\(appId ?? "")&is_mobile=true&meta=\(jsonString)&mobile=1"
                    
                    if flutter {
                        urlString += "&flutter_sdk_type=ios"
                    }
                    
                    print(urlString)
                    return urlString
                }
            } catch {
                print("Error: \(error.localizedDescription)")
                // Handle the error as needed
            }
        }

        return "" // Return a default value or handle this case accordingly
    }

}
