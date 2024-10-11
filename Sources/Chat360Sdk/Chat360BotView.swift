import SwiftUI
import WebKit


@available(iOS 13.0, *)
struct Chat360BotView: UIViewRepresentable {
    
    let botConfig: Chat360Config

    init(botConfig: Chat360Config) {
        self.botConfig = botConfig
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.navigationDelegate = context.coordinator
        webView.scrollView.isScrollEnabled = false
        
        if let uri = botConfig.createUrl() {
            webView.load(URLRequest(url: uri))
        } else {
            // Handle the case where the URL is nil
            print("Failed to create URL")
        }

        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        // Optionally handle updates to the view
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        let parent: Chat360BotView

        init(_ parent: Chat360BotView) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            print("Bot started loading.")
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            print("Bot finished loading.")
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            print("Bot failed with error: \(error.localizedDescription)")
        }
    }
}
