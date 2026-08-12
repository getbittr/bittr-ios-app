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
        
        SentryManager.start()

        // Migrate any legacy UserDefaults-stored secrets (mnemonic, PIN) into the
        // Keychain. Safe to call on every launch; a no-op once migrated. The
        // getters also self-heal on first read, so this is just eager cleanup.
        CacheManager.migrateSecretsToKeychainIfNeeded()

        // Convert any cache still stored in the pre-Codable shape.
        CacheManager.migrateCachesIfNeeded()
        
        // Keep Documents out of iCloud/Finder backups.
        LightningStorage.excludeFromBackup()
        
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
