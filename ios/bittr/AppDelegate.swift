//
//  AppDelegate.swift
//  bittr
//
//  Created by Tom Melters on 23/03/2023.
//

import UIKit
import Sentry
import UserNotifications

@main
class AppDelegate: UIResponder, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        
        SentrySDK.start { options in
            options.dsn = "https://a132893f0e0785733b108592f71efebc@o4507055777120256.ingest.us.sentry.io/4507055778758656"
            options.debug = false
            options.tracesSampleRate = 1.0
            options.sendDefaultPii = false
            options.environment = EnvironmentConfig.currentEnvironment.rawValue
            
            // Redact sensitive data in Sentry events.
            options.beforeSend = { sentryEvent in
                
                if let eventMessage = sentryEvent.message?.formatted {
                    sentryEvent.message = SentryMessage(formatted: eventMessage.redactBTCValues())
                }
                
                if let eventExceptions = sentryEvent.exceptions {
                    for eachException in eventExceptions {
                        eachException.value = eachException.value?.redactBTCValues()
                        if let exceptionMechanism = eachException.mechanism {
                            if let mechanismDescription = exceptionMechanism.desc {
                                eachException.mechanism!.desc = mechanismDescription.redactBTCValues()
                            }
                        }
                    }
                }
                
                if var eventExtra = sentryEvent.extra {
                    for (key, value) in eventExtra {
                        if let valueString = value as? String {
                            eventExtra[key] = valueString.redactBTCValues()
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
                
                // Send hardcoded build number to Sentry.
                if sentryEvent.extra == nil { sentryEvent.extra = [String:Any]() }
                
                return sentryEvent
            }
            
            // Redact sensitive data in traced HTTP spans.
            options.beforeSendSpan = { span in
                
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
            
            // Redact sensitive data in Sentry breadcrumbs.
            options.beforeBreadcrumb = { breadCrumb in
                
                let newBreadcrumb = breadCrumb
                
                // Redact HTTP query contents from breadcrumb.
                if var breadcrumbData = newBreadcrumb.data {
                    
                    // Redact http.query from breadcrumb.
                    if breadcrumbData["http.query"] != nil {
                        breadcrumbData["http.query"] = "[redacted]"
                    }
                    
                    // Redact UIButton tag from view data.
                    if let view = breadcrumbData["view"] as? String {
                        let redactedTag = view.replacingOccurrences(of: #"tag\s*=\s*\d+\s*;?"#, with: "tag = [redacted];", options: .regularExpression)
                        breadcrumbData["view"] = redactedTag
                    }
                    
                    // Redact UIButton tag from target data.
                    if let breadcrumbTarget = breadcrumbData["target"] as? String {
                        let redactedTarget = breadcrumbTarget.replacingOccurrences(of: #"tag\s*=\s*\d+\s*;?"#, with: "tag = [redacted];", options: .regularExpression)
                        breadcrumbData["target"] = redactedTarget
                    }
                    
                    // Redact URL.
                    if let url = breadcrumbData["url"] as? String {
                        breadcrumbData["url"] = url.redactURL()
                    }
                    // Redact HTTP query.
                    if breadcrumbData["http.query"] != nil {
                        breadcrumbData["http.query"] = "[redacted]"
                    }
                    
                    // Redact UIButton tag from breadcrumb.
                    if breadcrumbData["tag"] != nil {
                        breadcrumbData["tag"] = "[redacted]"
                    }
                    
                    // Redact accessibility identifier from UIButton.
                    if breadcrumbData["accessibilityIdentifier"] != nil {
                        breadcrumbData["accessibilityIdentifier"] = "[redacted]"
                    }
                    
                    newBreadcrumb.data = breadcrumbData
                }
                
                newBreadcrumb.message = newBreadcrumb.message?.replacingOccurrences(of: #"tag\s*=\s*\d+"#, with: "tag = [redacted]", options: .regularExpression).redactURL()
                
                return newBreadcrumb
            }
        }

        // Migrate any legacy UserDefaults-stored secrets (mnemonic, PIN) into the
        // Keychain. Safe to call on every launch; a no-op once migrated. The
        // getters also self-heal on first read, so this is just eager cleanup.
        CacheManager.migrateSecretsToKeychainIfNeeded()

        UNUserNotificationCenter.current().delegate = self
        
        return true
    }

    // MARK: UISceneSession Lifecycle

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        // Called when a new scene session is being created.
        // Use this method to select a configuration to create the new scene with.
        return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }

    func application(_ application: UIApplication, didDiscardSceneSessions sceneSessions: Set<UISceneSession>) {
        // Called when the user discards a scene session.
        // If any sessions were discarded while the application was not running, this will be called shortly after application:didFinishLaunchingWithOptions.
        // Use this method to release any resources that were specific to the discarded scenes, as they will not return.
    }
    
    func applicationWillTerminate(_ application: UIApplication) {
        DispatchQueue.global(qos: .background).async {
            try? BitcoinManager.shared.stop()
        }
    }
    
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        
        let tokenParts = deviceToken.map { data in String(format: "%02.2hhx", data) }
        let token = tokenParts.joined()
        print("Device Token: \(token)")
        
        // Cache token.
        CacheManager.storeNotificationsToken(token: token)
        
        // Send token to DeviceVC and Transfer15VC.
        NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "receivedToken"), object: nil, userInfo: ["token":token]) as Notification)
    }
    
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        Log.info("Failed to register: \(error)")
        // Tell whoever is waiting on the token (Transfer2's 2FA gate) instead
        // of only logging — an unanswered wait is an infinite spinner.
        NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "tokenRegistrationFailed"), object: nil, userInfo: nil) as Notification)
    }

}

extension String {
    
    func redactBTCValues() -> String {
        // Replace any sequence like "0.16450231 BTC" with "[redacted]"
        let pattern = #"[0-9]+\.[0-9]+(\s*BTC)?"#
        return self.replacingOccurrences(of: pattern, with: "[redacted]", options: .regularExpression)
    }
    
    func redactURL() -> String {
        // Regex pattern to catch URLs (both http and https)
        let pattern = #"(https?:\/\/[^\s]+)"#
        return self.replacingOccurrences(of: pattern, with: "[redacted URL]", options: .regularExpression)
    }
    
    func redactURLIdentifiers() -> String {
        
        // Drop any query and fragment wholesale.
        var url = self
        if let queryStart = url.firstIndex(where: { $0 == "?" || $0 == "#" }) {
            url = String(url[url.startIndex..<queryStart])
        }
        
        return url
            .split(separator: "/", omittingEmptySubsequences: false)
            .map { pathSegment in
                let isIdentifier = pathSegment.count >= 20 && pathSegment.allSatisfy { $0.isLetter || $0.isNumber }
                return isIdentifier ? "[redacted]" : String(pathSegment)
            }
            .joined(separator: "/")
    }
    
}

