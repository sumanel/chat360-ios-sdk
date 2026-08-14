import SwiftUI
import WebKit

@available(iOS 15.0, *)
public struct IframeContent: View {
    private let content: BotContent.IframeContent
    private let onAdvance: (String) -> Void

    public init(content: BotContent.IframeContent, onAdvance: @escaping (String) -> Void) {
        self.content = content
        self.onAdvance = onAdvance
    }

    public var body: some View {
        IframeWebView(content: content, onAdvance: onAdvance)
            .frame(height: CGFloat(content.heightDp ?? 240))
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

@available(iOS 15.0, *)
private struct IframeWebView: UIViewRepresentable {
    let content: BotContent.IframeContent
    let onAdvance: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onAdvance: onAdvance, targetId: content.targetId)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        if let moveForEvent = content.moveForEvent, !moveForEvent.isBlank, content.targetId != nil {
            let controller = WKUserContentController()
            controller.add(context.coordinator, name: "Chat360IframeBridge")
            controller.addUserScript(WKUserScript(source: bridgeScript(moveForEvent), injectionTime: .atDocumentEnd, forMainFrameOnly: true))
            configuration.userContentController = controller
        }
        let webView = WKWebView(frame: .zero, configuration: configuration)
        if let url = URL(string: content.url) {
            webView.load(URLRequest(url: url))
        }
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    private func bridgeScript(_ moveForEvent: String) -> String {
        let escaped = moveForEvent.replacingOccurrences(of: "\"", with: "\\\"")
        return """
        (function() {
          if (window.__chat360BridgeInstalled) return;
          window.__chat360BridgeInstalled = true;
          window.addEventListener('message', function(e) {
            try {
              if (e.origin === window.location.origin && e.data && e.data.type === "\(escaped)") {
                window.webkit.messageHandlers.Chat360IframeBridge.postMessage("advance");
              }
            } catch (err) {}
          });
        })();
        """
    }

    final class Coordinator: NSObject, WKScriptMessageHandler {
        let onAdvance: (String) -> Void
        let targetId: String?

        init(onAdvance: @escaping (String) -> Void, targetId: String?) {
            self.onAdvance = onAdvance
            self.targetId = targetId
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if let targetId { onAdvance(targetId) }
        }
    }
}
