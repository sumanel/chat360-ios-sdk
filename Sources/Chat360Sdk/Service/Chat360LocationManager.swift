import Foundation
import CoreLocation

@objc
@available(iOS 13.0, *)
class Chat360LocationManager: NSObject, CLLocationManagerDelegate {

    // MARK: - Singleton
    @objc static let shared = Chat360LocationManager()

    private let manager = CLLocationManager()
    private var completion: ((Double, Double) -> Void)?

    private override init() {
        super.init()
        print("[Chat360LocationManager] INIT: Setting delegate & accuracy")
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    // MARK: - Public API
    @objc
    func requestLocation(_ completion: @escaping (Double, Double) -> Void) {
        print("[Chat360LocationManager] requestLocation() CALLED")
        self.completion = completion

        let status = CLLocationManager.authorizationStatus()
        print("[Chat360LocationManager] Current authorization status: \(status.rawValue)")

        switch status {

        case .notDetermined:
            print("[Chat360LocationManager] NOT_DETERMINED → Requesting permission…")
            manager.requestWhenInUseAuthorization()

        case .authorizedWhenInUse, .authorizedAlways:
            print("[Chat360LocationManager] AUTHORIZED → Requesting location…")
            manager.requestLocation()

        case .restricted:
            print("[Chat360LocationManager] ERROR: Permission RESTRICTED")
            completion(0, 0)
            self.completion = nil

        case .denied:
            print("[Chat360LocationManager] ERROR: Permission DENIED")
            completion(0, 0)
            self.completion = nil

        @unknown default:
            print("[Chat360LocationManager] ERROR: Unknown authorization state")
            completion(0, 0)
            self.completion = nil
        }
    }

    // MARK: - Authorization Changed (iOS 13+ Compatible)
    func locationManager(_ manager: CLLocationManager,
                         didChangeAuthorization status: CLAuthorizationStatus) {

        print("[Chat360LocationManager] didChangeAuthorization → \(status.rawValue)")

        switch status {

        case .authorizedWhenInUse, .authorizedAlways:
            print("[Chat360LocationManager] Permission GRANTED → Requesting location…")
            manager.requestLocation()

        case .denied:
            print("[Chat360LocationManager] ERROR: User DENIED permission")
            completion?(0, 0)
            completion = nil

        case .restricted:
            print("[Chat360LocationManager] ERROR: Permission RESTRICTED")
            completion?(0, 0)
            completion = nil

        case .notDetermined:
            print("[Chat360LocationManager] Waiting for user decision…")

        @unknown default:
            print("[Chat360LocationManager] ERROR: Unknown authorization state")
            completion?(0, 0)
            completion = nil
        }
    }

    // MARK: - Location Success
    func locationManager(_ manager: CLLocationManager,
                         didUpdateLocations locations: [CLLocation]) {

        print("[Chat360LocationManager] didUpdateLocations CALLED with \(locations.count) locations")

        guard let loc = locations.first else {
            print("[Chat360LocationManager] ERROR: No valid location found")
            completion?(0, 0)
            completion = nil
            return
        }

        let lat = loc.coordinate.latitude
        let lng = loc.coordinate.longitude

        print("[Chat360LocationManager] SUCCESS: lat=\(lat), lng=\(lng)")

        completion?(lat, lng)
        completion = nil
    }

    // MARK: - Location Error
    func locationManager(_ manager: CLLocationManager,
                         didFailWithError error: Error) {

        print("[Chat360LocationManager] didFailWithError: \(error.localizedDescription)")
        print("[Chat360LocationManager] ERROR DETAILS: \(error)")

        completion?(0, 0)
        completion = nil
    }
}
