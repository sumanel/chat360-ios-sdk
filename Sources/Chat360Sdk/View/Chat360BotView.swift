import SwiftUI
import WebKit

@available(iOS 13.0, *)
public struct Chat360BotView: UIViewRepresentable {
    let botConfig: Chat360Config

    public init(botConfig: Chat360Config) {
        self.botConfig = botConfig
        registerDefaultHandlers()
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    public func makeUIView(context: Context) -> WKWebView {
        let contentController = WKUserContentController()
        contentController.add(context.coordinator, name: "jsBridge")
        contentController.add(context.coordinator, name: "consoleBridge")

        let jsBridge = """
        (function() {
            // --- Override console.log ---
            var oldLog = console.log;
            console.log = function() {
                var msg = Array.from(arguments).map(a => {
                    try { return JSON.stringify(a); } catch(e) { return String(a); }
                }).join(' ');
                if (window.webkit && window.webkit.messageHandlers.consoleBridge) {
                    window.webkit.messageHandlers.consoleBridge.postMessage(msg);
                }
                oldLog.apply(console, arguments);
            };

            // --- Send events to native via jsBridge ---
            window.sendToApp = function(event) {
                if (!event || !event.type) {
                    console.log('sendToApp requires event.type');
                    return;
                }
                if (window.webkit && window.webkit.messageHandlers.jsBridge) {
                    window.webkit.messageHandlers.jsBridge.postMessage(event);
                } else {
                    console.log("jsBridge not available:", event);
                }
            };

            // --- Receive events from native ---
            window.receiveFromApp = function(event) {
                console.log("Received from app:", event);
                if (window.onAppEvent) {
                    window.onAppEvent(event);
                }
            };
        })();
        """

        let userScript = WKUserScript(source: jsBridge, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        contentController.addUserScript(userScript)

        let config = WKWebViewConfiguration()
        config.userContentController = contentController

        let webView = WKWebView(frame: .zero, configuration: config)
        context.coordinator.webView = webView
        webView.scrollView.isScrollEnabled = false
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator

        if let uri = botConfig.createUrl() {
            print("[Chat360Bot] Bot started uri \(uri.absoluteString).")
            webView.load(URLRequest(url: uri))
        } else {
            print("[Chat360Bot] Failed to create URL")
        }

        return webView
    }

    public func updateUIView(_: WKWebView, context _: Context) {}

    public class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler, WKUIDelegate {
        let parent: Chat360BotView
        var webView: WKWebView?

        public init(_ parent: Chat360BotView) {
            self.parent = parent
        }

        // ✅ Correct signatures
        public func webView(_ webView: WKWebView, didStartProvisionalNavigation _: WKNavigation!) {
            self.webView = webView
            Chat360JSBridge.shared.webView = webView
            print("[Chat360Bot] Bot started loading.")
        }

        public func webView(_ webView: WKWebView, didFinish _: WKNavigation!) {
            self.webView = webView
            Chat360JSBridge.shared.webView = webView
            print("[Chat360Bot] Bot finished loading.")
        }

        public func webView(_ webView: WKWebView, didFail _: WKNavigation!, withError error: Error) {
            self.webView = webView
            Chat360JSBridge.shared.webView = webView
            print("[Chat360Bot] Bot failed with error: \(error.localizedDescription)")
        }

        public func userContentController(_: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "consoleBridge" && parent.botConfig.isDebug {
                print("[JS Console]:", message.body)
                return
            }

            if message.name == "jsBridge" {
                guard let body = message.body as? [String: Any],
                      let type = body["type"] as? String
                else {
                    print("[NativeBridge] Invalid message:", message.body)
                    return
                }

                if let webView = webView {
                    let data = body["data"] as? [String: String] ?? [:]
                    EventDispatcher.shared.handle(event: type, data: data, webView: webView)
                }
            }
        }
    }

    private func registerDefaultHandlers() {
        EventDispatcher.shared.register(event: "CHAT360_WINDOW_EVENT") { webView, body  in
            let metadata: [String: String]
            if let provider = Chat360Bot.shared.handleWindowEvents?(body) {
                metadata = provider
            } else {
                metadata = [:]
            }

            self.postResponse(webView: webView, type: "CHAT360_WINDOW_EVENT_RESPONSE", data: metadata)
        }
    }

    public func postResponse(webView: WKWebView, type: String, data: [String: String]) {
        guard let jsonData = try? JSONSerialization.data(withJSONObject: data),
              let jsonString = String(data: jsonData, encoding: .utf8)
        else {
            print("[Native → JS] Failed to encode response")
            return
        }

        let js = """
        window.receiveFromApp({ type: "\(type)", data: \(jsonString) });
        """

        DispatchQueue.main.async {
            webView.evaluateJavaScript(js) { _, error in
                if let error = error {
                    print("[Native → JS] Error sending message:", error.localizedDescription)
                } else {
                    print("[Native → JS] Sent event \(type)")
                }
            }
        }
    }
}
