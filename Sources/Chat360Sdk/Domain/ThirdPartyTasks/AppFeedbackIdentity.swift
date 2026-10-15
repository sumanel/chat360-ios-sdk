import Foundation

/// Who an application-wide feedback is from. The host's own dealer/employee win; otherwise the values it passed in
/// `meta` (`dealer_id` / `emp_id`) are used, and the end-user id is the employee of last resort. Blank counts as unset.
struct AppFeedbackIdentity: Equatable {
    let dealerId: String?
    let empId: String?

    static func resolve(dealerId: String?, empId: String?, meta: [String: String]?, endUserId: String?) -> AppFeedbackIdentity {
        func clean(_ value: String?) -> String? {
            guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
            return trimmed
        }
        return AppFeedbackIdentity(
            dealerId: clean(dealerId) ?? clean(meta?["dealer_id"]),
            empId: clean(empId) ?? clean(meta?["emp_id"]) ?? clean(endUserId)
        )
    }
}
