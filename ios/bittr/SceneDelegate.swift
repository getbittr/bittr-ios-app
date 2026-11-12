//
//  SceneDelegate.swift
//  bittr
//
//  Created by Tom Melters on 23/03/2023.
//

import UIKit
import LDKNode
import Sentry

class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?


    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let _ = (scene as? UIWindowScene) else { return }
        
        // Handle URIs when app is launched from a completely killed state
        if !connectionOptions.urlContexts.isEmpty {
            // Handle Bitcoin and Lightning URIs
            if let paymentContext = connectionOptions.urlContexts.first(where: { $0.url.isPaymentLink }) {
                self.handlePaymentURI(paymentContext.url)
                return
            }
            
            // Tapped a swap Live Activity from a fully-killed app (cold launch).
            if let bittrContext = connectionOptions.urlContexts.first(where: { $0.url.scheme == "bittr" }) {
                self.handleBittrDeepLink(bittrContext.url)
                return
            }
        }
        
        self.launchBittrValue(urlContexts: connectionOptions.urlContexts, delay: 1.8)
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        // Called as the scene is being released by the system.
        // This occurs shortly after the scene enters the background, or when its session is discarded.
        // Release any resources associated with this scene that can be re-created the next time the scene connects.
        // The scene may re-connect later, as its session was not necessarily discarded (see `application:didDiscardSceneSessions` instead).
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        // Called when the scene has moved from an inactive state to an active state.
        // Use this method to restart any tasks that were paused (or not yet started) when the scene was inactive.
        // Process pending notifications when scene becomes active
        self.processPendingNotifications()
    }
    
    private func processPendingNotifications() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            if let lastNotification = CacheManager.getLastNotification(), !lastNotification.hasBeenHandled {
                Log.info("sceneDelegate did find unhandled cached notification. Will handle.")
                lastNotification.handle()
            }
        }
    }

    func sceneWillResignActive(_ scene: UIScene) {
        // Called when the scene will move from an active state to an inactive state.
        // This may occur due to temporary interruptions (ex. an incoming phone call).
    }

    func sceneWillEnterForeground(_ scene: UIScene) {
        // Called as the scene transitions from the background to the foreground.
        // Use this method to undo the changes made on entering the background.
        
        NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "setupblur"), object: nil, userInfo: nil) as Notification)
        
        // Clean up any swap Live Activity that finished or went stale while we were backgrounded.
        SwapLiveActivityController.endStaleActivities()
        
        DispatchQueue.global(qos: .background).async {
            if BitcoinManager.shared.status()?.isRunning == true {
                Log.info("Check peer connection upon entering foreground.")
                if !isConnectedToPeer() {
                    Task {
                        _ = await BitcoinManager.shared.connectToLightningPeer()
                    }
                }
            } else {
                Log.info("Node not running upon entering foreground.")
            }
        }
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        // Called as the scene transitions from the foreground to the background.
        // Use this method to save data, release shared resources, and store enough scene-specific state information
        // to restore the scene back to its current state.
    }
    
    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        
        // Handle Bitcoin and Lightning URIs
        if let paymentContext = URLContexts.first(where: { $0.url.isPaymentLink }) {
            self.handlePaymentURI(paymentContext.url)
            return
        }

        // Tapped a swap Live Activity (Dynamic Island / Lock Screen).
        if let bittrContext = URLContexts.first(where: { $0.url.scheme == "bittr" }) {
            self.handleBittrDeepLink(bittrContext.url)
            return
        }

        // Handle existing widget deeplink
        self.launchBittrValue(urlContexts: URLContexts, delay: 0)
    }

    // Routes a bittr:// deep link from a tapped swap Live Activity.
    private func handleBittrDeepLink(_ url: URL) {
        switch url.host {
        case "resumeswap":
            // Set flag and check when the wallet has loaded.
            UserDefaults.standard.set(true, forKey: "pendingSwapResume")
            NotificationCenter.default.post(name: NSNotification.Name(rawValue: "resumeSwapPayment"), object: nil)
        case "swapstatus":
            NotificationCenter.default.post(name: NSNotification.Name(rawValue: "openSwapStatus"), object: nil)
        default:
            break
        }
    }
    
    private func handlePaymentURI(_ url: URL) {
        Log.debug("Received payment URI: \(url.absoluteString)")
        
        // The send screen reads the link with the same parser as a scanned or pasted code.
        let uriData: [String: Any] = ["code": url.absoluteString]
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "handlePaymentURI"), object: nil, userInfo: uriData) as Notification)
        }
    }
    
    private func launchBittrValue(urlContexts: Set<UIOpenURLContext>, delay:Double) {
        
        guard let _: UIOpenURLContext = urlContexts.first(where: { $0.url.scheme == "widget-deeplink" }) else { return }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "openvalue"), object: nil, userInfo: nil) as Notification)
        }
    }


}

extension URL {
    
    var isPaymentLink: Bool {
        ["bitcoin", "lightning"].contains(self.scheme?.lowercased())
    }
}
