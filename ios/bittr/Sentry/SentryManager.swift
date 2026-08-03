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
    
    static func start() {
        
        SentrySDK.start { options in
            options.dsn = "https://a132893f0e0785733b108592f71efebc@o4507055777120256.ingest.us.sentry.io/4507055778758656"
            options.debug = false
            
            // Filter events that get sent to Sentry.
            options.tracesSampleRate = 0.1
            options.sendDefaultPii = false
            options.environment = EnvironmentConfig.currentEnvironment.rawValue
            options.enableCaptureFailedRequests = false
            options.enableWatchdogTerminationTracking = false
            options.appHangTimeoutInterval = 5.0
            options.enableReportNonFullyBlockingAppHangs = false

            // Redact sensitive data before anything leaves the device.
            options.beforeSend = { redacted(event: $0) }
            options.beforeSendSpan = { redacted(span: $0) }
            options.beforeBreadcrumb = { redacted(breadcrumb: $0) }
        }
    }
    
    // Qualified: LDKNode has an Event of its own, and this file imports both.
    private static func redacted(event sentryEvent:Sentry.Event) -> Sentry.Event {
        
        if let eventMessage = sentryEvent.message?.formatted {
            sentryEvent.message = SentryMessage(formatted: eventMessage.redactSensitiveValues())
        }
        
        if let eventExceptions = sentryEvent.exceptions {
            for eachException in eventExceptions {
                eachException.value = eachException.value?.redactSensitiveValues()
                if let mechanismDescription = eachException.mechanism?.desc {
                    eachException.mechanism?.desc = mechanismDescription.redactSensitiveValues()
                }
            }
        }
        
        if var eventExtra = sentryEvent.extra {
            for (key, value) in eventExtra {
                if let valueString = value as? String {
                    eventExtra[key] = valueString.redactSensitiveValues()
                }
            }
            sentryEvent.extra = eventExtra
        }
        
        if let eventRequest = sentryEvent.request {
            eventRequest.url = eventRequest.url?.redactURLIdentifiers()
            eventRequest.queryString = nil
            eventRequest.fragment = nil
            eventRequest.cookies = nil
            eventRequest.headers = nil
        }
        
        // Redact sensitive user data.
        if sentryEvent.user != nil {
            
            // Redact IP address.
            sentryEvent.user!.ipAddress = "[redacted]"
            
            // Redact geo data.
            sentryEvent.user!.geo = Geo()
            sentryEvent.user!.geo!.countryCode = "[redacted]"
            sentryEvent.user!.geo!.city = "[redacted]"
            sentryEvent.user!.geo!.region = "[redacted]"
        }
        
        if sentryEvent.context != nil {
            if sentryEvent.context!["culture"] != nil {
                for (key, _) in sentryEvent.context!["culture"]! {
                    sentryEvent.context!["culture"]![key]! = "[redacted]"
                }
            }
            if sentryEvent.context!["device"] != nil {
                if sentryEvent.context!["device"]!["locale"] != nil {
                    sentryEvent.context!["device"]!["locale"]! = "[redacted]"
                }
            }
        }
        
        // Send device token to Sentry.
        if let deviceToken = CacheManager.getRegistrationToken() {
            if sentryEvent.extra == nil { sentryEvent.extra = [String:Any]() }
            sentryEvent.extra!["device_token"] = deviceToken
        }
        
        return sentryEvent
    }
    
    private static func redacted(span:Span) -> Span {
        
        span.spanDescription = span.spanDescription?.redactURLIdentifiers()
        
        if let spanURL = span.data["url"] as? String {
            span.setData(value: spanURL.redactURLIdentifiers(), key: "url")
        }
        if span.data["http.query"] != nil {
            span.setData(value: "[redacted]", key: "http.query")
        }
        if span.data["http.fragment"] != nil {
            span.setData(value: "[redacted]", key: "http.fragment")
        }
        
        return span
    }
    
    private static func redacted(breadcrumb:Breadcrumb) -> Breadcrumb {
        
        if var breadcrumbData = breadcrumb.data {
            
            if breadcrumbData["http.query"] != nil {
                breadcrumbData["http.query"] = "[redacted]"
            }
            if breadcrumbData["http.fragment"] != nil {
                breadcrumbData["http.fragment"] = "[redacted]"
            }
            
            // Keep the endpoint that was called, drop what it was called with.
            if let url = breadcrumbData["url"] as? String {
                breadcrumbData["url"] = url.redactURLIdentifiers()
            }
            
            // Redact UIButton tag from view and target data.
            for key in ["view", "target"] {
                if let value = breadcrumbData[key] as? String {
                    breadcrumbData[key] = value.replacingOccurrences(of: #"tag\s*=\s*\d+\s*;?"#, with: "tag = [redacted];", options: .regularExpression)
                }
            }
            
            // Redact UIButton tag and accessibility identifier.
            if breadcrumbData["tag"] != nil {
                breadcrumbData["tag"] = "[redacted]"
            }
            if breadcrumbData["accessibilityIdentifier"] != nil {
                breadcrumbData["accessibilityIdentifier"] = "[redacted]"
            }
            
            breadcrumb.data = breadcrumbData
        }
        
        breadcrumb.message = breadcrumb.message?
            .replacingOccurrences(of: #"tag\s*=\s*\d+"#, with: "tag = [redacted]", options: .regularExpression)
            .redactURLs()
        
        return breadcrumb
    }
    
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
        guard EnvironmentConfig.isProduction else { return }
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
