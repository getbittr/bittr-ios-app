//
//  SentryManager.swift
//  bittr
//
//  Created by Tom Melters on 8/3/26.
//

import Sentry
import UIKit

enum SentryManager {
    
    static func capture(_ error: any Error, context:String? = nil) {
        DispatchQueue.main.async {
            SentrySDK.capture(error: error) { scope in
                if let context { scope.setExtra(value: context, key: "context") }
            }
        }
    }
    
    static func capture(_ message:String, context:String? = nil) {
        DispatchQueue.main.async {
            SentrySDK.capture(message: message) { scope in
                if let context { scope.setExtra(value: context, key: "context") }
            }
        }
    }
    
    static func countMetric(_ key:String) {
        DispatchQueue.main.async {
            SentrySDK.metrics.count(key: key)
        }
    }
}
