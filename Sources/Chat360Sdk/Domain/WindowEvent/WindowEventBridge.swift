import Foundation

public final class WindowEventBridge {
    public static let shared = WindowEventBridge()

    private var activeSessionSender: (([String: String]) -> Void)?
    private var receiving = false

    private init() {}

    public func registerSession(_ sender: @escaping ([String: String]) -> Void) {
        activeSessionSender = sender
    }

    public func unregisterSession() {
        activeSessionSender = nil
        receiving = false
    }

    public func setReceiving(_ enabled: Bool) {
        receiving = enabled
    }

    public func dispatchToHost(handleWindowEvent: (([String: String]) -> [String: String])?, sendData: [String: String]) -> [String: String] {
        handleWindowEvent?(sendData) ?? [:]
    }

    public func sendToActiveSession(_ event: [String: String]) {
        guard receiving else { return }
        activeSessionSender?(event)
    }
}
