import CoreLocation
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

            // --- Geolocation API Polyfill ---
            // if (!navigator.geolocation) {
                navigator.geolocation = {};
            // }

            // Store original or create new geolocation object
            var geolocationImpl = navigator.geolocation;
            var pendingCallbacks = {};
            var callbackId = 0;

            navigator.geolocation.getCurrentPosition = function(successCallback, errorCallback, options) {
                console.log("geolocation available: getCurrentPosition called");
                var id = ++callbackId;
                pendingCallbacks[id] = {
                    success: successCallback,
                    error: errorCallback
                };

                // Send request to native
                if (window.webkit && window.webkit.messageHandlers.jsBridge) {
                    window.webkit.messageHandlers.jsBridge.postMessage({
                        type: 'GET_LOCATION',
                        data: {
                            callbackId: id.toString()
                        }
                    });
                }
            };

            navigator.geolocation.watchPosition = function(successCallback, errorCallback, options) {
                var id = ++callbackId;
                pendingCallbacks[id] = {
                    success: successCallback,
                    error: errorCallback
                };

                if (window.webkit && window.webkit.messageHandlers.jsBridge) {
                    window.webkit.messageHandlers.jsBridge.postMessage({
                        type: 'WATCH_LOCATION',
                        data: {
                            callbackId: id.toString()
                        }
                    });
                }
                return id;
            };

            navigator.geolocation.clearWatch = function(watchId) {
                delete pendingCallbacks[watchId];
            };

            // Handle location response from native
            window.handleLocationResponse = function(callbackId, latitude, longitude, accuracy) {
                if (pendingCallbacks[callbackId]) {
                    var position = {
                        coords: {
                            latitude: parseFloat(latitude),
                            longitude: parseFloat(longitude),
                            accuracy: parseFloat(accuracy) || 0,
                            altitude: null,
                            altitudeAccuracy: null,
                            heading: null,
                            speed: null
                        },
                        timestamp: Date.now()
                    };
                    pendingCallbacks[callbackId].success(position);
                    delete pendingCallbacks[callbackId];
                }
            };

            window.handleLocationError = function(callbackId, code, message) {
                if (pendingCallbacks[callbackId]) {
                    var error = {
                        code: parseInt(code) || 1,
                        message: message || 'Unknown error'
                    };
                    if (pendingCallbacks[callbackId].error) {
                        pendingCallbacks[callbackId].error(error);
                    }
                    delete pendingCallbacks[callbackId];
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

    public class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler, WKUIDelegate, CLLocationManagerDelegate {
        let parent: Chat360BotView
        var webView: WKWebView?
        var locationPermissionHandler: ((Bool) -> Void)?
        var locationManager: CLLocationManager?
        var geolocationCompletionHandlers: [String: (CLLocationCoordinate2D) -> Void] = [:]
        var watchingLocationCallbacks: [String: (CLLocationCoordinate2D) -> Void] = [:]
        var pendingLocationCallbackIds: [String] = []

        public init(_ parent: Chat360BotView) {
            self.parent = parent
            super.init()
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
            if message.name == "consoleBridge", parent.botConfig.isDebug {
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

        // MARK: - WKNavigationDelegate for URL handling

        public func webView(
            _: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            if let url = navigationAction.request.url {
                let urlString = url.absoluteString

                // Allow bot internal URLs
                if let host = url.host,
                   let botId = parent.botConfig.botId,
                   host.contains(botId)
                {
                    decisionHandler(.allow)
                    return
                }

                // Allow localhost for development
                if url.scheme == "http" || url.scheme == "https" {
                    if let host = url.host,
                       host == "localhost" || host.contains("127.0.0.1")
                    {
                        decisionHandler(.allow)
                        return
                    }
                }

                // Open external links outside the app
                if navigationAction.targetFrame == nil || navigationAction.navigationType == .linkActivated {
                    if #available(iOS 10.0, *) {
                        UIApplication.shared.open(url, options: [:], completionHandler: nil)
                    } else {
                        UIApplication.shared.openURL(url)
                    }
                    decisionHandler(.cancel)
                    return
                }
            }

            decisionHandler(.allow)
        }

        // MARK: - WKUIDelegate for permissions and window handling

        @available(iOS 15.0, *)
        public func webView(_: WKWebView, requestMediaCapturePermissionFor _: WKSecurityOrigin, initiatedByFrame _: WKFrameInfo, type _: WKMediaCaptureType, decisionHandler: @escaping (WKPermissionDecision) -> Void) {
            decisionHandler(.grant)
        }

        @available(iOS 15.0, *)
        public func webView(_: WKWebView, requestDeviceOrientationAndMotionPermissionFor _: WKSecurityOrigin, initiatedByFrame _: WKFrameInfo, decisionHandler: @escaping (WKPermissionDecision) -> Void) {
            decisionHandler(.grant)
        }

        @available(iOS 15.0, *)
        public func webView(_: WKWebView, requestGeolocationPermissionFor _: WKSecurityOrigin, initiatedByFrame _: WKFrameInfo, decisionHandler: @escaping (WKPermissionDecision) -> Void) {
            if parent.botConfig.isDebug {
                print("[Chat360Bot] Geolocation permission requested")
            }

            // Check current authorization status
            let status = CLLocationManager.authorizationStatus()

            if parent.botConfig.isDebug {
                print("[Chat360Bot] Current location auth status: \(status.rawValue)")
            }

            switch status {
            case .authorizedAlways, .authorizedWhenInUse:
                if parent.botConfig.isDebug {
                    print("[Chat360Bot] Location already authorized, granting permission")
                }
                decisionHandler(.grant)
                // Request location immediately
                requestCurrentLocation()
            case .denied, .restricted:
                if parent.botConfig.isDebug {
                    print("[Chat360Bot] Location access denied or restricted")
                }
                decisionHandler(.deny)
            case .notDetermined:
                if parent.botConfig.isDebug {
                    print("[Chat360Bot] Location permission not determined, requesting")
                }
                // For iOS 15.0+, request location access
                decisionHandler(.prompt)
                setupLocationManager()
            @unknown default:
                if parent.botConfig.isDebug {
                    print("[Chat360Bot] Unknown location auth status")
                }
                decisionHandler(.prompt)
            }
        }

        // MARK: - Location Management

        private func setupLocationManager() {
            if parent.botConfig.isDebug {
                print("[Chat360Bot] Setting up location manager")
            }

            if locationManager == nil {
                locationManager = CLLocationManager()
                locationManager?.delegate = self
                locationManager?.desiredAccuracy = kCLLocationAccuracyBest

                if parent.botConfig.isDebug {
                    print("[Chat360Bot] Location manager initialized with delegate")
                }
            }

            if parent.botConfig.isDebug {
                print("[Chat360Bot] Requesting when-in-use authorization on main thread")
            }

            // Ensure the location manager has the delegate set
            if locationManager?.delegate == nil {
                locationManager?.delegate = self
                if parent.botConfig.isDebug {
                    print("[Chat360Bot] Delegate was nil, reassigned to self")
                }
            }

            // Must be called on main thread
            DispatchQueue.main.async {
                if self.parent.botConfig.isDebug {
                    print("[Chat360Bot] Calling requestWhenInUseAuthorization on main thread")
                }
                self.locationManager?.requestWhenInUseAuthorization()
            }

            if parent.botConfig.isDebug {
                print("[Chat360Bot] Authorization request dispatched to main thread")
            }
        }

        private func requestCurrentLocation() {
            if parent.botConfig.isDebug {
                print("[Chat360Bot] Requesting current location")
                print("[Chat360Bot] Current pending completion handlers: \(geolocationCompletionHandlers.keys)")
            }

            if locationManager == nil {
                if parent.botConfig.isDebug {
                    print("[Chat360Bot] Location manager is nil, setting up")
                }
                setupLocationManager()
                return
            }

            if parent.botConfig.isDebug {
                print("[Chat360Bot] Calling requestLocation() on main thread")
            }

            // Must be called on main thread
            DispatchQueue.main.async {
                self.locationManager?.requestLocation()
            }
        }

        public func locationManager(_: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
            guard let location = locations.last else {
                if parent.botConfig.isDebug {
                    print("[Chat360Bot] No locations received")
                }
                return
            }

            if parent.botConfig.isDebug {
                print("[Chat360Bot] Location updated: \(location.coordinate.latitude), \(location.coordinate.longitude)")
                print("[Chat360Bot] Pending callbacks count: \(geolocationCompletionHandlers.count)")
            }

            // Return location to all pending callbacks
            for (callbackId, _) in geolocationCompletionHandlers {
                if parent.botConfig.isDebug {
                    print("[Chat360Bot] Sending location to callback: \(callbackId)")
                }
                sendLocationToWebView(callbackId: callbackId, coordinate: location.coordinate)
            }
            geolocationCompletionHandlers.removeAll()

            // Continue watching for location changes
            for (callbackId, _) in watchingLocationCallbacks {
                if parent.botConfig.isDebug {
                    print("[Chat360Bot] Sending watched location to callback: \(callbackId)")
                }
                sendLocationToWebView(callbackId: callbackId, coordinate: location.coordinate)
            }
        }

        public func locationManager(_: CLLocationManager, didFailWithError error: Error) {
            if parent.botConfig.isDebug {
                print("[Chat360Bot] Location manager error: \(error.localizedDescription)")
            }

            // Send error to all pending callbacks
            for (callbackId, _) in geolocationCompletionHandlers {
                if parent.botConfig.isDebug {
                    print("[Chat360Bot] Sending location error to callback: \(callbackId)")
                }
                sendLocationErrorToWebView(callbackId: callbackId, error: error)
            }
            geolocationCompletionHandlers.removeAll()
        }

        @available(iOS 14.0, *)
        public func locationManagerDidChangeAuthorization(_: CLLocationManager) {
            if parent.botConfig.isDebug {
                print("[Chat360Bot] Location authorization status changed")
            }

            let status = CLLocationManager.authorizationStatus()

            if parent.botConfig.isDebug {
                print("[Chat360Bot] New authorization status: \(status.rawValue)")
            }

            switch status {
            case .authorizedAlways, .authorizedWhenInUse:
                if parent.botConfig.isDebug {
                    print("[Chat360Bot] Location now authorized, requesting location for \(pendingLocationCallbackIds.count) pending callbacks")
                }
                // Store all pending callback IDs in completion handlers
                for callbackId in pendingLocationCallbackIds {
                    geolocationCompletionHandlers[callbackId] = { _ in }
                }
                requestCurrentLocation()
            case .denied, .restricted:
                if parent.botConfig.isDebug {
                    print("[Chat360Bot] Location permission denied or restricted")
                }
                // Send error to all pending callbacks
                for callbackId in pendingLocationCallbackIds {
                    sendLocationErrorToWebView(callbackId: callbackId, error: NSError(domain: "LocationError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Permission denied"]))
                }
                pendingLocationCallbackIds.removeAll()
            default:
                break
            }
        }

        // Fallback for iOS 13 and older
        public func locationManager(_: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
            if parent.botConfig.isDebug {
                print("[Chat360Bot] didChangeAuthorization (iOS 13) called with status: \(status.rawValue)")
            }

            switch status {
            case .authorizedAlways, .authorizedWhenInUse:
                if parent.botConfig.isDebug {
                    print("[Chat360Bot] Location authorized (iOS 13), requesting location for \(pendingLocationCallbackIds.count) pending callbacks")
                }
                // Store all pending callback IDs in completion handlers
                for callbackId in pendingLocationCallbackIds {
                    geolocationCompletionHandlers[callbackId] = { _ in }
                }
                requestCurrentLocation()
            case .denied, .restricted:
                if parent.botConfig.isDebug {
                    print("[Chat360Bot] Location permission denied/restricted (iOS 13)")
                }
                for callbackId in pendingLocationCallbackIds {
                    sendLocationErrorToWebView(callbackId: callbackId, error: NSError(domain: "LocationError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Permission denied"]))
                }
                pendingLocationCallbackIds.removeAll()
            default:
                break
            }
        }

        private func sendLocationToWebView(callbackId: String, coordinate: CLLocationCoordinate2D) {
            guard let webView = webView else {
                if parent.botConfig.isDebug {
                    print("[Chat360Bot] WebView is nil, cannot send location")
                }
                return
            }

            if parent.botConfig.isDebug {
                print("[Chat360Bot] Preparing to send location via JS for callback: \(callbackId)")
            }

            let js = """
            window.handleLocationResponse('\(callbackId)', \(coordinate.latitude), \(coordinate.longitude), 0);
            """

            DispatchQueue.main.async {
                webView.evaluateJavaScript(js) { _, error in
                    if let error = error {
                        if self.parent.botConfig.isDebug {
                            print("[Chat360Bot] Error sending location:", error.localizedDescription)
                        }
                    } else {
                        if self.parent.botConfig.isDebug {
                            print("[Chat360Bot] Location sent to callback \(callbackId)")
                        }
                    }
                }
            }
        }

        private func sendLocationErrorToWebView(callbackId: String, error: Error) {
            guard let webView = webView else {
                if parent.botConfig.isDebug {
                    print("[Chat360Bot] WebView is nil, cannot send location error")
                }
                return
            }

            if parent.botConfig.isDebug {
                print("[Chat360Bot] Preparing to send location error via JS for callback: \(callbackId)")
            }

            let errorMessage = error.localizedDescription.replacingOccurrences(of: "'", with: "\\'")
            let js = """
            window.handleLocationError('\(callbackId)', 1, '\(errorMessage)');
            """

            DispatchQueue.main.async {
                webView.evaluateJavaScript(js) { _, error in
                    if let error = error {
                        if self.parent.botConfig.isDebug {
                            print("[Chat360Bot] Error sending location error:", error.localizedDescription)
                        }
                    } else {
                        if self.parent.botConfig.isDebug {
                            print("[Chat360Bot] Location error sent to callback \(callbackId)")
                        }
                    }
                }
            }
        }

        func requestLocationViaEvent(callbackId: String, webView: WKWebView) {
            if parent.botConfig.isDebug {
                print("[Chat360Bot] Requesting location via event for callbackId: \(callbackId)")
            }

            self.webView = webView

            // Send event to app to provide location
            let event: [String: String] = [
                "type": "REQUEST_LOCATION",
                "callbackId": callbackId,
            ]

            // Notify the app that location is needed
            if let onLocationNeeded = Chat360Bot.shared.onLocationNeeded {
                if parent.botConfig.isDebug {
                    print("[Chat360Bot] Calling onLocationNeeded callback")
                }
                onLocationNeeded(callbackId) { latitude, longitude in
                    if self.parent.botConfig.isDebug {
                        print("[Chat360Bot] Received location: \(latitude), \(longitude)")
                    }
                    self.sendLocationToWebView(callbackId: callbackId, latitude: latitude, longitude: longitude)
                }
            } else {
                if parent.botConfig.isDebug {
                    print("[Chat360Bot] onLocationNeeded callback not set, sending error")
                }
                // Send error since no location provider is available
                let js = """
                window.handleLocationError('\(callbackId)', 1, 'Location provider not configured');
                """
                DispatchQueue.main.async {
                    self.webView?.evaluateJavaScript(js)
                }
            }
        }

        func watchLocationViaEvent(callbackId: String, webView: WKWebView) {
            if parent.botConfig.isDebug {
                print("[Chat360Bot] Watching location via event for callbackId: \(callbackId)")
            }

            self.webView = webView

            if let onLocationNeeded = Chat360Bot.shared.onLocationNeeded {
                if parent.botConfig.isDebug {
                    print("[Chat360Bot] Calling onLocationNeeded callback for watch")
                }
                onLocationNeeded(callbackId) { latitude, longitude in
                    if self.parent.botConfig.isDebug {
                        print("[Chat360Bot] Received watched location: \(latitude), \(longitude)")
                    }
                    self.sendLocationToWebView(callbackId: callbackId, latitude: latitude, longitude: longitude)
                }
            } else {
                if parent.botConfig.isDebug {
                    print("[Chat360Bot] onLocationNeeded callback not set, sending error")
                }
                // Send error since no location provider is available
                let js = """
                window.handleLocationError('\(callbackId)', 1, 'Location provider not configured');
                """
                DispatchQueue.main.async {
                    self.webView?.evaluateJavaScript(js)
                }
            }
        }

        private func sendLocationToWebView(callbackId: String, latitude: String, longitude: String) {
            guard let webView = webView else {
                if parent.botConfig.isDebug {
                    print("[Chat360Bot] WebView is nil, cannot send location")
                }
                return
            }

            if parent.botConfig.isDebug {
                print("[Chat360Bot] Sending location \(latitude), \(longitude) to callback: \(callbackId)")
            }

            let js = """
            window.handleLocationResponse('\(callbackId)', \(latitude), \(longitude), 0);
            """

            DispatchQueue.main.async {
                webView.evaluateJavaScript(js) { _, error in
                    if let error = error {
                        if self.parent.botConfig.isDebug {
                            print("[Chat360Bot] Error sending location:", error.localizedDescription)
                        }
                    } else {
                        if self.parent.botConfig.isDebug {
                            print("[Chat360Bot] Location sent successfully to callback \(callbackId)")
                        }
                    }
                }
            }
        }
    }

    private func registerDefaultHandlers() {
        EventDispatcher.shared.register(event: "CHAT360_WINDOW_EVENT") { webView, body in
            let metadata: [String: String]
            if let provider = Chat360Bot.shared.handleWindowEvents?(body) {
                metadata = provider
            } else {
                metadata = [:]
            }

            self.postResponse(webView: webView, type: "CHAT360_WINDOW_EVENT_RESPONSE", data: metadata)
        }

        EventDispatcher.shared.register(event: "GET_LOCATION") { [self] webView, body in
            let callbackId = body["callbackId"] ?? ""

            if self.botConfig.isDebug {
                print("[Chat360Bot] GET_LOCATION handler called with callbackId: \(callbackId)")
            }

            // Request location from the app delegate
            if let coordinator = webView.navigationDelegate as? Coordinator {
                DispatchQueue.main.async {
                    coordinator.requestLocationViaEvent(callbackId: callbackId, webView: webView)
                }
            }
        }

        EventDispatcher.shared.register(event: "WATCH_LOCATION") { [self] webView, body in
            let callbackId = body["callbackId"] ?? ""

            if self.botConfig.isDebug {
                print("[Chat360Bot] WATCH_LOCATION handler called with callbackId: \(callbackId)")
            }

            if let coordinator = webView.navigationDelegate as? Coordinator {
                DispatchQueue.main.async {
                    coordinator.watchLocationViaEvent(callbackId: callbackId, webView: webView)
                }
            }
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
