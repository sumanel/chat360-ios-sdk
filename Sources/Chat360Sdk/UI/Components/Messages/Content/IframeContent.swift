import SwiftUI
import WebKit

/// Implements the IFRAME node's `postMessage` auto-advance: the bot flow must jump forward when
/// the embedded page posts a `message` event with `data.type === moveForEvent`. A native
/// `WKWebView` has no parent/child browsing context to listen from outside, so the equivalent
/// here is injecting a small script into the embedded page itself that listens on its *own*
/// `window` and relays a match back to Swift through a `WKScriptMessageHandler`.
struct IframeContent: View {
    var content: BotContent.IframeContent
    var onAdvance: (String) -> Void

    var body: some View {
        IframeWebView(content: content, onAdvance: onAdvance)
            .frame(height: CGFloat(content.heightDp ?? 240))
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

private struct IframeWebView: UIViewRepresentable {
    var content: BotContent.IframeContent
    var onAdvance: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(targetId: content.targetId, onAdvance: onAdvance)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        if let moveForEvent = content.moveForEvent, !moveForEvent.isEmpty, content.targetId != nil {
            let userContentController = WKUserContentController()
            userContentController.add(context.coordinator, name: "chat360IframeBridge")
            userContentController.addUserScript(WKUserScript(
                source: bridgeScript(moveForEvent: moveForEvent),
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true
            ))
            configuration.userContentController = userContentController
        }
        let webView = WKWebView(frame: .zero, configuration: configuration)
        if let url = URL(string: content.url) {
            webView.load(URLRequest(url: url))
        }
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        if let url = URL(string: content.url), webView.url != url {
            webView.load(URLRequest(url: url))
        }
    }

    private func bridgeScript(moveForEvent: String) -> String {
        let data = (try? JSONEncoder().encode(moveForEvent)).flatMap { String(data: $0, encoding: .utf8) } ?? "\"\""
        return """
        (function() {
          if (window.__chat360BridgeInstalled) return;
          window.__chat360BridgeInstalled = true;
          window.addEventListener('message', function(e) {
            try {
              if (e.origin === window.location.origin && e.data && e.data.type === \(data)) {
                window.webkit.messageHandlers.chat360IframeBridge.postMessage('advance');
              }
            } catch (err) {}
          });
        })();
        """
    }

    final class Coordinator: NSObject, WKScriptMessageHandler {
        let targetId: String?
        let onAdvance: (String) -> Void
        init(targetId: String?, onAdvance: @escaping (String) -> Void) {
            self.targetId = targetId
            self.onAdvance = onAdvance
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let targetId else { return }
            onAdvance(targetId)
        }
    }
}
