import Foundation
import UIKit
import SwiftUI

@objc
@available(iOS 13.0, *)
public class ChatController: UIViewController {
    @objc let botConfig: Chat360Config

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
        addHostingController(for: makeRootView())
    }

    @ViewBuilder
    private func makeRootView() -> some View {
        if botConfig.useNewUI, #available(iOS 16.0, *) {
            Chat360NativeChatScreen(botConfig: botConfig)
        } else {
            Chat360BotScreen(botConfig: botConfig)
        }
    }

    private func addHostingController(for rootView: some View) {
        let hostingController = UIHostingController(rootView: rootView)
        addChild(hostingController)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hostingController.view)
        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        hostingController.didMove(toParent: self)
    }
}
