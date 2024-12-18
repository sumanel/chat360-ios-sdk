import Foundation
import UIKit
import SwiftUI

@available(iOS 13.0, *)
class ChatController: UIViewController {
    let botConfig: Chat360Config

    public init(botConfig: Chat360Config) {
        self.botConfig = botConfig
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        let botView = Chat360BotScreen(botConfig: botConfig)
        let hostingController = UIHostingController(rootView: botView)
        addChild(hostingController)
        hostingController.view.frame = self.view.bounds
        hostingController.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(hostingController.view)
        hostingController.didMove(toParent: self)
    }
}
