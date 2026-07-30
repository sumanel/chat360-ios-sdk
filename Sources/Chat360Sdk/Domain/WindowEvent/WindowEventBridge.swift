import Foundation

/// Replaces `Chat360JSBridge`: the same two-way seam (a bot-authored WINDOW_EVENT node talking to
/// the host app), but as direct in-process Swift calls instead of `WKWebView` message handlers.
/// There is no JSON stringify/parse anywhere in this path since both sides are already native.
///
/// Outbound (bot -> host): a WINDOW_EVENT node with `shouldSend == true` calls `dispatchToHost`,
/// which invokes the host's `Chat360Bot.handleWindowEvents` callback directly and returns its
/// result.
///
/// Inbound (host -> bot): `Chat360Bot.sendEventToBot(event:)` ultimately calls
/// `sendToActiveSession`, which - only while the most recently rendered WINDOW_EVENT node has
/// `shouldReceive == true` - forwards the event into the active chat session as an outgoing
/// message.
enum WindowEventBridge {
    private static var activeSessionSender: (([String: String]) -> Void)?
    private static var receiving = false

    static func registerSession(_ sender: @escaping ([String: String]) -> Void) {
        activeSessionSender = sender
    }

    static func unregisterSession() {
        activeSessionSender = nil
        receiving = false
    }

    /// Called by `ChatRepository` whenever a bot message arrives - only WINDOW_EVENT nodes set this true.
    static func setReceiving(_ enabled: Bool) {
        receiving = enabled
    }

    static func dispatchToHost(_ handleWindowEvent: (([String: String]) -> [String: String])?, sendData: [String: String]) -> [String: String] {
        handleWindowEvent?(sendData) ?? [:]
    }

    static func sendToActiveSession(_ event: [String: String]) {
        guard receiving else { return }
        activeSessionSender?(event)
    }
}
