import Foundation
import Network

@available(iOS 13.0, *)
public enum Constants {
    public static var unreadMessageCount: Int = 0

    public static func isNetworkAvailable(_ completion: @escaping (Bool) -> Void) {
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { path in
            completion(path.status == .satisfied)
            monitor.cancel()
        }
        monitor.start(queue: DispatchQueue.global(qos: .utility))
    }
}
