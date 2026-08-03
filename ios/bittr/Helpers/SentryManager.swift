//
//  SentryManager.swift
//  bittr
//
//  Created by Tom Melters on 8/3/26.
//

import Sentry
import UIKit
import LDKNode

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

private enum Connectivity {
    
    static let urlErrorCodes:Set<URLError.Code> = [
        .notConnectedToInternet,
        .timedOut,
        .networkConnectionLost,
        .cannotConnectToHost,
        .cannotFindHost,
        .dnsLookupFailed,
        .dataNotAllowed,
        .internationalRoamingOff
    ]
    
    static let localizedDescriptions:Set<String> = Set(urlErrorCodes.map { URLError($0).localizedDescription })
}

extension Error {
    
    var isConnectivityError:Bool {
        
        if let urlError = self as? URLError {
            return Connectivity.urlErrorCodes.contains(urlError.code)
        }
        
        if let nodeError = self as? NodeError, case .ConnectionFailed = nodeError {
            return true
        }
        
        if let serviceError = self as? BittrServiceError {
            switch serviceError {
            case .networkError(let underlying), .other(let underlying):
                return underlying.isConnectivityError
            default:
                return false
            }
        }
        
        if let apiError = self as? APIError, case .requestFailed(let message) = apiError {
            return Connectivity.localizedDescriptions.contains(message)
        }
        
        return (self as NSError).domain == "Timeout"
    }
}
