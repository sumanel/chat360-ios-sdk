//
//  ChatLauncher.swift
//  Chat360SDK
//
//  Created by Sanchit Kumar Singh on 12/03/22.
//

import Foundation
import UIKit

public class ChatLauncher{
    public static func showChat(with config: ChatConfigs, parentController: UIViewController){
        let chatVC = ChatWebViewController.init(nibName: "ChatWebViewController", bundle: nil)
        chatVC.modalPresentationStyle = .pageSheet
        chatVC.config = config
        parentController.present(chatVC, animated: true) {
            
        }
    }
}

public struct ChatConfigs{
    var baseUrl: String = "https://app.chat360.io/page?h="
    private var stagingUrl = "https://app.gaadibaazar.in/page?h="
    var botId: String? = ""
    var appId: String? = ""
    var isDebug: Bool = false
    
    public init(botId: String, appId: String,deviceToken: String = "", isDebug: Bool = false){
        self.botId = botId
        self.appId = appId
        self.isDebug = isDebug
    }
    
    func createUrl() -> String{
        if isDebug{
            return "\(stagingUrl)\(botId ?? "")&store_session=1&app_id=\(appId ?? "")"
        }else{
            return "\(baseUrl)\(botId ?? "")&store_session=1&app_id=\(appId ?? "")"
        }
    }
}
