import UIKit
import WebKit

public class Chat360: UIViewController, WKUIDelegate {
    var webView: WKWebView!
    var appId: String
    var botId: String
    
    public init(appId: String, botId: String) {
            self.appId = appId
            self.botId = botId
            super.init(nibName: nil, bundle: nil)
        }
        
    required public init?(coder: NSCoder) {
           fatalError("init(coder:) has not been implemented")
       }
    
    override public func loadView() {
        let webConfiguration = WKWebViewConfiguration()
        webView = WKWebView(frame: .zero, configuration: webConfiguration)
                webView.uiDelegate = self
                view = webView
    }
    override public func viewDidLoad() {
        super.viewDidLoad()
        let value = UIInterfaceOrientation.landscapeLeft.rawValue
        UIDevice.current.setValue(value, forKey: "orientation")
        // Create WKWebView

//       appId="https://app.chat360.io/page/?h="

        DispatchQueue.global().async { [weak self] in
              guard let self = self else { return }

              let urlString = "https://app.gaadibaazar.in//page/?h=\(self.botId)&store_session=1&fcm_token=nil&app_id=\(self.appId)&is_mobile=true"
              if let url = URL(string: urlString) {
                  let request = URLRequest(url: url)
                  DispatchQueue.main.async { [weak self] in
                      self?.webView.load(request)
                  }
              }
          }
        
        if #available(iOS 15.0, *) {
            // Use WKMediaCaptureType
            
            webView.configuration.mediaTypesRequiringUserActionForPlayback = .all        }
        else {
            // Handle older iOS versions
            // Provide an alternative implementation or handle the logic accordingly
            // For example:
             webView.configuration.requiresUserActionForMediaPlayback = false
        }
    }
    public override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .portrait
    }

    public override var shouldAutorotate: Bool {
        return false
    }
    
    public override func viewSafeAreaInsetsDidChange() {
        if #available(iOS 11.0, *) {
            super.viewSafeAreaInsetsDidChange()
        } else {
            // Fallback on earlier versions
        }

        if #available(iOS 11.0, *) {
            let bottomSafeAreaInset = view.safeAreaInsets.bottom
        } else {
            // Fallback on earlier versions
        }
        webView.frame.size.height = view.bounds.height - bottomSafeAreaInset
    }

}
