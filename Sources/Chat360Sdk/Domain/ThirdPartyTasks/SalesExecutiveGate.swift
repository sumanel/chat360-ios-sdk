import Foundation

/// What `third-party-tasks/sales-exectives` says about the sales executive using the chat.
public struct SalesExecutiveResult: Equatable {
    public let success: Bool
    /// The server's own wording, e.g. "Sales Executive onboarded as INACTIVE.".
    public let message: String?
    /// `ACTIVE` / `INACTIVE` (compared case-insensitively), or nil when the reply carried none.
    public let status: String?

    public init(success: Bool, message: String?, status: String?) {
        self.success = success
        self.message = message
        self.status = status
    }

    public var isInactive: Bool { success && status?.caseInsensitiveCompare("INACTIVE") == .orderedSame }
}

/// Resumes a continuation exactly once, whichever of two racing tasks gets there first.
@available(iOS 13.0, *)
private final class ResumeOnce<T> {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T?, Never>?

    init(_ continuation: CheckedContinuation<T?, Never>) { self.continuation = continuation }

    func resume(_ value: T?) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(returning: value)
    }
}

/// Decides whether the chat is closed for this sales executive, the same way maintenance mode closes it: the
/// socket never opens and the message replaces the input bar.
///
/// The rule is deliberately narrow. The chat is blocked ONLY when the server answers successfully and says the
/// executive is INACTIVE. Every other outcome - no network, a timeout, a 404 (endpoint not deployed), a 400
/// validation error, an error page, `success: false`, an unknown or missing status, an ACTIVE status - lets the
/// user through and the bot flow run exactly as it would without this check. A check that is silently broken must
/// never lock anyone out.
///
/// `details` is the host app's map (`dealer_code` and `emp_code` are required by the server; `name`, `status` and
/// anything else are optional) and is sent as the JSON body untouched.
@available(iOS 13.0, *)
public actor SalesExecutiveGate {
    public static let defaultTimeout: TimeInterval = 3
    public static let defaultMessage = "Your access is currently inactive. Please contact your administrator."

    private let apiService: ThirdPartyTasksApiService
    private let clientId: String
    private let details: [String: String]
    private let timeout: TimeInterval
    private var clearedForThisSession = false
    // Overlapping callers (start-up and a foreground resume, say) share one request instead of each sending their own.
    private var inFlight: Task<String?, Never>?

    public init(apiService: ThirdPartyTasksApiService, clientId: String, details: [String: String], timeout: TimeInterval = SalesExecutiveGate.defaultTimeout) {
        self.apiService = apiService
        self.clientId = clientId
        self.details = details
        self.timeout = timeout
    }

    /// The message to show while the chat is closed to this executive, or nil to let them through.
    public func blockedMessage() async -> String? {
        if let running = inFlight { return await running.value }
        let task = Task { await self.evaluate() }
        inFlight = task
        let result = await task.value
        inFlight = nil
        return result
    }

    private func evaluate() async -> String? {
        // Once the server has said "not inactive" the answer is kept for the session: a later deactivation is
        // delivered by the server closing the socket, so re-asking on every foreground would only add traffic.
        if clearedForThisSession { return nil }
        guard !(details["dealer_code"] ?? "").isBlank, !(details["emp_code"] ?? "").isBlank else { return nil }

        let api = apiService, id = clientId, body = details, seconds = timeout
        let result = await Self.firstToFinish(within: seconds) { try await api.checkSalesExecutive(clientId: id, details: body, timeout: seconds) }
        guard let result else { return nil }
        if result.isInactive {
            let message = result.message ?? ""
            return message.isBlank ? Self.defaultMessage : message
        }
        if result.success, !(result.status ?? "").isBlank { clearedForThisSession = true }
        return nil
    }

    /// The operation's result, or nil if it fails or takes longer than `seconds`. Returns the moment either happens
    /// - it does not wait for a slow request to finish, which a task group would.
    private static func firstToFinish<T>(within seconds: TimeInterval, _ operation: @escaping () async throws -> T) async -> T? {
        await withCheckedContinuation { (continuation: CheckedContinuation<T?, Never>) in
            let once = ResumeOnce(continuation)
            Task {
                do { once.resume(try await operation()) } catch {
                    NSLog("[Chat360] sales-exectives check failed - letting the user through: %@", error.localizedDescription)
                    once.resume(nil)
                }
            }
            Task {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                once.resume(nil)
            }
        }
    }
}
