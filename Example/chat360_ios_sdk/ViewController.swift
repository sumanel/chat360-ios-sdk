import UIKit
import chat360_ios_sdk

class ViewController: UIViewController {

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        let config = ChatConfigs(botId: "f0efe1c0-cbe9-4320-859b-e594cd7fc46f", appId: "com.chat360.chat360demoapp")
        ChatLauncher.showChat(with: config, parentController: self)
    }
    
    // ...
}
