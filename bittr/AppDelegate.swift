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
            options.debug = false // Enabled debug when first installing is always helpful
            options.enableTracing = true
            
            // Redact sensitive data in Sentry events.
            options.beforeSend = { sentryEvent in
                
                if let eventMessage = sentryEvent.message?.formatted {
                    sentryEvent.message = SentryMessage(formatted: eventMessage.redactBTCValues())
                }
                
                if let eventExceptions = sentryEvent.exceptions {
                    for eachException in eventExceptions {
                        eachException.value = eachException.value.redactBTCValues()
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
                
                return sentryEvent
            }
            
            // Redact sensitive data in Sentry breadcrumbs.
            options.beforeBreadcrumb = { breadCrumb in
                
                // Redact data from button presses.
                if breadCrumb.category == "ui.action" || breadCrumb.category == "ui.click" {
                    var newBreadcrumb = breadCrumb
                    
                    if var breadcrumbData = newBreadcrumb.data {
                        
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
                        
                        // Redact UIButton tag from breadcrumb.
                        if breadcrumbData["tag"] != nil {
                            breadcrumbData["tag"] = "[redacted]"
                        }
                        
                        // Redact http.query from breadcrumb.
                        if breadcrumbData["http.query"] != nil {
                            breadcrumbData["http.query"] = "[redacted]"
                        }
                        
                        newBreadcrumb.data = breadcrumbData
                    }
                    
                    newBreadcrumb.message = newBreadcrumb.message?.replacingOccurrences(of: #"tag\s*=\s*\d+"#, with: "tag = [redacted]", options: .regularExpression)
                    
                    return newBreadcrumb
                }
                return breadCrumb
            }

            // Uncomment the following lines to add more data to your events
            // options.attachScreenshot = true // This adds a screenshot to the error events
            // options.attachViewHierarchy = true // This adds the view hierarchy to the error events
        }

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
        try? LightningNodeService.shared.stop()
    }
    
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        
        let tokenParts = deviceToken.map { data in String(format: "%02.2hhx", data) }
        let token = tokenParts.joined()
        print("Device Token: \(token)")
        NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "showtoken"), object: nil, userInfo: ["token":token]) as Notification)
        
        CacheManager.storeNotificationsToken(token: token)
        NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "resume2fa"), object: nil, userInfo: nil) as Notification)
    }
    
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("Failed to register: \(error)")
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        
        // Handle the notification content even when app is in foreground
        let userInfo = notification.request.content.userInfo
        
        if let specialData = userInfo["bittr_specific_data"] as? [String: Any] {
            // Handle Lightning payment notifications in foreground
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "handlepaymentnotification"), object: nil, userInfo: userInfo) as Notification)
            }
        } else if let specialData = userInfo["bittr_notification"] as? [String: Any] {
            // Handle Bittr notifications in foreground
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "handlebittrnotification"), object: nil, userInfo: userInfo) as Notification)
            }
        } else if let swapData = userInfo["swap_notification"] as? [String: Any] {
            // Handle swap-specific notifications in foreground
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "swapNotification"), object: nil, userInfo: swapData) as Notification)
            }
        } else if let lightningAddressData = userInfo["lightning_address_notification"] as? [String: Any] {
            // Handle lightning address payment requests in foreground
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "lightningAddressNotification"), object: nil, userInfo: lightningAddressData) as Notification)
            }
        } else {
            self.handleUnexpectedNotification(4)
        }
        
        completionHandler(.alert)
    }
    
    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable : Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        
        // Print entire userInfo dictionary to console
        print("Received remote notification: \(userInfo)")
        
        // Only handle background notifications here, not foreground ones
        // Foreground notifications are handled in willPresent method
        if UIApplication.shared.applicationState != .active {
            if let actualUserInfo = userInfo as [AnyHashable:Any]? {
                // Check if it's a Lightning payment or another message.
                if let specialData = userInfo["bittr_specific_data"] as? [String: Any] {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "handlepaymentnotification"), object: nil, userInfo: userInfo) as Notification)
                    }
                } else if let specialData = userInfo["bittr_notification"] as? [String: Any] {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "handlebittrnotification"), object: nil, userInfo: userInfo) as Notification)
                    }
                } else if let swapData = userInfo["swap_notification"] as? [String: Any] {
                    // Handle swap-specific notifications
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "swapNotification"), object: nil, userInfo: swapData) as Notification)
                    }
                } else if let lightningAddressData = userInfo["lightning_address_notification"] as? [String: Any] {
                    // Handle lightning address payment requests
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "lightningAddressNotification"), object: nil, userInfo: lightningAddressData) as Notification)
                    }
                } else {
                    // Unexpected notification type.
                    self.handleUnexpectedNotification(1)
                }
            } else {
                self.handleUnexpectedNotification(2)
            }
        } else {
            self.handleUnexpectedNotification(3)
        }
    }

    func handleUnexpectedNotification(_ typeNumber:Int) {
        let notificationData:[String:Any] = ["header_text":Language.getWord(withID: "notification"),"body_text":"\(Language.getWord(withID: "notificationhandlingfail")) [\(typeNumber)]"]
        let userInfo:[AnyHashable:Any] = ["bittr_notification":notificationData]
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            SentrySDK.capture(message: "Received notification with unexpected type \(typeNumber).")
            NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "handlebittrnotification"), object: nil, userInfo: userInfo) as Notification)
        }
    }

}

extension String {
    
    func redactBTCValues() -> String {
        // Replace any sequence like "0.16450231 BTC" with "[redacted]"
        let pattern = #"[0-9]+\.[0-9]+(\s*BTC)?"#
        return self.replacingOccurrences(of: pattern, with: "[redacted]", options: .regularExpression)
    }
}

