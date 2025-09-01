//
//  EventDispatcher.swift
//  Chat360SDK
//
//  Created by Harshit Sharma on 01/09/25.
//

import Foundation
import WebKit
import SwiftUI


@available(iOS 13.0, *)
public class EventDispatcher {
    static let shared = EventDispatcher()
    private var handlers: [String: (WKWebView, [String: Any]?) -> Void] = [:]
    
    private init() {}
    
    public func register(event type: String, handler: @escaping (WKWebView, [String: Any]?) -> Void) {
        handlers[type] = handler
    }
    
    func handle(event type: String, data: [String: Any]?, webView: WKWebView) {
        if let handler = handlers[type] {
            handler(webView, data)
        } else {
            print("[EventDispatcher] No handler registered for event type: \(type)")
        }
    }
}
