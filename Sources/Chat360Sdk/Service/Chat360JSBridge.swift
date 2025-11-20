//
//  Chat360JSBridge.swift
//  Chat360SDK
//
//  Created by Harshit Sharma on 20/11/25.
//

import WebKit
import SwiftUI

@available(iOS 13.0, *)
public class Chat360JSBridge {
    public static let shared = Chat360JSBridge()
    
    private init() {}

    weak var webView: WKWebView?

    public func send(type: String, data: [String: String]) {
        guard let webView = webView else {
            print("[Native → JS] ERROR: webView not available")
            return
        }

        guard let jsonData = try? JSONSerialization.data(withJSONObject: data),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            print("[Native → JS] JSON encoding failure")
            return
        }

        let js = """
        window.receiveFromApp({ type: "\(type)", data: \(jsonString) });
        """

        DispatchQueue.main.async {
            webView.evaluateJavaScript(js) { _, error in
                if let error = error {
                    print("[Native → JS] Error:", error.localizedDescription)
                } else {
                    print("[Native → JS] Sent event \(type)")
                }
            }
        }
    }
}
