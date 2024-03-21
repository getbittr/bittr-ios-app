//
//  AppDelegate.swift
//  bittr
//
//  Created by Tom Melters on 23/03/2023.
//

import UIKit
import UserNotifications

@main
class AppDelegate: UIResponder, UIApplicationDelegate, UNUserNotificationCenterDelegate {



    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
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
        
        completionHandler(.alert)
    }
    
    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable : Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        
        // Print entire userInfo dictionary to console
        print("Received remote notification: \(userInfo)")
        
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
            }
        }
    }


}

