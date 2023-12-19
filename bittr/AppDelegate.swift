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

        // Check for the special key that indicates this is a silent notification.
        if let specialData = userInfo["bittr_specific_data"] as? [String: Any] {
            print("Received special data: \(specialData)")

            // Extract required data from specialData
            if let notificationId = specialData["notification_id"] as? String {
                let bitcoinAmountString = specialData["bitcoin_amount"] as? String ?? "0"
                let bitcoinAmount = Double(bitcoinAmountString) ?? 0.0
                let amountMsat = UInt64(bitcoinAmount * 100_000_000_000)
                
                let pubkey = LightningNodeService.shared.nodeId()

                
                // Call payoutLightning in an async context
                Task.init {
                    let invoice = try await LightningNodeService.shared.receivePayment(
                        amountMsat: amountMsat,
                        description: notificationId,
                        expirySecs: 3600
                    )
                    
                    let lightningSignature = try await LightningNodeService.shared.signMessage(message: notificationId)
                    
                    do {
                        let payoutResponse = try await BittrService.shared.payoutLightning(notificationId: notificationId, invoice: invoice, signature: lightningSignature, pubkey: pubkey)
                        print("Payout successful. PreImage: \(payoutResponse.preImage ?? "N/A")")
                        completionHandler(.newData)
                    } catch {
                        print("Error occurred: \(error.localizedDescription)")
                        completionHandler(.failed)
                    }
                }
            } else {
                print("Required data not found in notification.")
                completionHandler(.noData)
            }
        } else {
            // No special key, so this is a normal notification.
            print("No special key found in notification.")
            completionHandler(.noData)
        }
        
    }


}

