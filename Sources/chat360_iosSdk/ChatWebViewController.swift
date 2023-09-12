import UIKit
import WebKit

 class ChatWebViewController: UIViewController, WKNavigationDelegate, WKUIDelegate {
    
    private var webView: WKWebView!
    var config: ChatConfigs?

    override func viewDidLoad() {
        super.viewDidLoad()
        configureNavigationBar()
        configureChatWebView()
    }
     
     private func configureNavigationBar() {
             let closeButton = UIBarButtonItem(title: "Close", style: .plain, target: self, action: #selector(closeButtonTapped))
             navigationItem.rightBarButtonItem = closeButton
         let refreshButton = UIBarButtonItem(title: "Refresh", style: .plain, target: self, action: #selector(refreshButtonTapped))
         navigationItem.leftBarButtonItem = refreshButton
         }
     
     @objc private func closeButtonTapped() {
             closeWebView()
         }
     @objc private func refreshButtonTapped() {
         webView.reload()
         }
    
    private func configureChatWebView() {
        if let url = config?.createUrl(), let urlToLoad = URL(string: url){
            let request = URLRequest(url: urlToLoad)
            webView.load(request)
//            injectJavaScriptCode()
        }
    }
    
    override func loadView() {
        let config = WKWebViewConfiguration()
        config.preferences.javaScriptCanOpenWindowsAutomatically = true
        webView = WKWebView(frame: .zero, configuration: config)
        webView.uiDelegate = self
        webView.navigationDelegate = self
        self.view = webView
    }
  
    
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        // Check if the navigation action is a link click and decide to allow it
        if navigationAction.navigationType == .linkActivated {
            if let url = navigationAction.request.url {
                UIApplication.shared.open(url) // Open links in Safari or default browser
                decisionHandler(.cancel) // Cancel the navigation so it doesn't load in the WKWebView
                return
            }
        }
        decisionHandler(.allow) // Allow all other navigation actions
    }
     
     // Inject JavaScript code into the web page to handle button clicks and close the webview
        func injectJavaScriptCode() {
            let jsCode = """
                // Add click event listener to your button element by its ID or any other selector
                document.querySelector(".cursor-pointer").addEventListener('click', function() {
                    // Handle button click here, for example, you can post a message to the iOS app
                    // using window.webkit.messageHandlers to communicate with the native code
                    // For simplicity, here we are calling a function named 'buttonClicked' in iOS native code
                                       window.webkit.messageHandlers.closeWebView.postMessage("Close webview!");
                });

                // Function to close the webview
                function closeWebView() {
                    window.webkit.messageHandlers.closeWebView.postMessage("Close webview!");
                }
            """
            
            let userScript = WKUserScript(source: jsCode, injectionTime: .atDocumentStart, forMainFrameOnly: true)
                    let userContentController = WKUserContentController()
                    userContentController.addUserScript(userScript)

                    userContentController.add(self, name: "closeWebViewHandler")
                    webView.configuration.userContentController = userContentController
        }
}
extension ChatWebViewController: WKScriptMessageHandler {
    // Handle messages posted from JavaScript
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
      if message.name == "closeWebView" {
            if let body = message.body as? String {
                print("Close WebView: \(body)")
                // Handle the request to close the webview here
                closeWebView()
            }
        }
    }
    
    // Function to close the webview
    private func closeWebView() {
        // Dismiss the current view controller to close the webview
        self.dismiss(animated: true, completion: nil)
    }
    
    
  
}
