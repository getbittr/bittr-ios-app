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

            // Uncomment the following lines to add more data to your events
            // options.attachScreenshot = true // This adds a screenshot to the error events
            // options.attachViewHierarchy = true // This adds the view hierarchy to the error events
        }
        // Remove the next line after confirming that your Sentry integration is working.
        //SentrySDK.capture(message: "This app uses Sentry! :)")

        // Override point for customization after application launch.
        
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
        
        if let swapData = userInfo["swap_notification"] as? [String: Any] {
            // Handle swap-specific notifications in foreground
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "swapNotification"), object: nil, userInfo: swapData) as Notification)
            }
        } else if let lightningAddressData = userInfo["lightning_address_notification"] as? [String: Any] {
            // Handle lightning address payment requests in foreground
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "lightningAddressNotification"), object: nil, userInfo: lightningAddressData) as Notification)
            }
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
                }
            }
        }
    }


}

