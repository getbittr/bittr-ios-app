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
        // Use this method to optionally configure and attach the UIWindow `window` to the provided UIWindowScene `scene`.
        // If using a storyboard, the `window` property will automatically be initialized and attached to the scene.
        // This delegate does not imply the connecting scene or session are new (see `application:configurationForConnectingSceneSession` instead).
        guard let _ = (scene as? UIWindowScene) else { return }
        
        // Handle URIs when app is launched from a completely killed state
        if !connectionOptions.urlContexts.isEmpty {
            // Handle Bitcoin and Lightning URIs
            if let bitcoinContext = connectionOptions.urlContexts.first(where: { $0.url.scheme == "bitcoin" }) {
                self.handleBitcoinURI(bitcoinContext.url)
                return
            }
            
            if let lightningContext = connectionOptions.urlContexts.first(where: { $0.url.scheme == "lightning" }) {
                self.handleLightningURI(lightningContext.url)
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
        processPendingNotifications()
    }
    
    private func processPendingNotifications() {
        // Check if we have a pending payment notification
        if let pendingPaymentNotification = UserDefaults.standard.dictionary(forKey: "pendingPaymentNotification") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "handlepaymentnotification"), object: nil, userInfo: pendingPaymentNotification) as Notification)
            }
            UserDefaults.standard.removeObject(forKey: "pendingPaymentNotification")
        }
        
        // Check if we have a pending Bittr notification
        if let pendingBittrNotification = UserDefaults.standard.dictionary(forKey: "pendingBittrNotification") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "handlebittrnotification"), object: nil, userInfo: pendingBittrNotification) as Notification)
            }
            UserDefaults.standard.removeObject(forKey: "pendingBittrNotification")
        }
        
        // Check if we have a pending swap notification
        if let pendingSwapNotification = UserDefaults.standard.dictionary(forKey: "pendingSwapNotification") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "swapNotification"), object: nil, userInfo: pendingSwapNotification) as Notification)
            }
            UserDefaults.standard.removeObject(forKey: "pendingSwapNotification")
        }
        
        // Check if we have a pending lightning address notification
        if let pendingLightningAddressNotification = UserDefaults.standard.dictionary(forKey: "pendingLightningAddressNotification") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "lightningAddressNotification"), object: nil, userInfo: pendingLightningAddressNotification) as Notification)
            }
            UserDefaults.standard.removeObject(forKey: "pendingLightningAddressNotification")
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
        
        DispatchQueue.global(qos: .background).async {
            do {
                if let nodeStatus = LightningNodeService.shared.status(), nodeStatus.isRunning {
                    print("Will sync LDK node upon entering foreground.")
                    try LightningNodeService.shared.syncWallets()
                }
            } catch {
                DispatchQueue.main.async {
                    SentrySDK.capture(error: error) { scope in
                        scope.setExtra(value: "SceneDelegate row 68", key: "context")
                    }
                }
                let errorMessage:String = {
                    if let nodeError = error as? NodeError {
                        return handleNodeError(nodeError).title + ", " + handleNodeError(nodeError).detail
                    } else {
                        return error.localizedDescription
                    }
                }()
                print("Could not sync LDK node. Error: \(errorMessage)")
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
        if let bitcoinContext = URLContexts.first(where: { $0.url.scheme == "bitcoin" }) {
            self.handleBitcoinURI(bitcoinContext.url)
            return
        }
        
        if let lightningContext = URLContexts.first(where: { $0.url.scheme == "lightning" }) {
            self.handleLightningURI(lightningContext.url)
            return
        }
        
        // Handle existing widget deeplink
        self.launchBittrValue(urlContexts: URLContexts, delay: 0)
    }
    
    private func handleBitcoinURI(_ url: URL) {
        print("Received Bitcoin URI: \(url.absoluteString)")
        
        // Parse Bitcoin URI: bitcoin:address?amount=0.001&label=description
        // Extract address from the URL - it's everything after "bitcoin:" and before "?"
        let urlString = url.absoluteString
        let address: String
        var amount: String?
        var label: String?
        
        if let questionMarkIndex = urlString.firstIndex(of: "?") {
            // Extract address (everything between "bitcoin:" and "?")
            let addressStart = urlString.index(urlString.startIndex, offsetBy: 8) // Skip "bitcoin:"
            address = String(urlString[addressStart..<questionMarkIndex])
        } else {
            // No query parameters, address is everything after "bitcoin:"
            let addressStart = urlString.index(urlString.startIndex, offsetBy: 8) // Skip "bitcoin:"
            address = String(urlString[addressStart...])
        }
        
        // Parse query parameters
        var lightningInvoice: String?
        if let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems {
            for item in queryItems {
                if item.name == "amount" {
                    amount = item.value
                } else if item.name == "label" {
                    label = item.value
                } else if item.name == "lightning" {
                    lightningInvoice = item.value
                }
            }
        }
        
        // If there's a lightning parameter, treat this as a Lightning payment
        if let lightning = lightningInvoice, !lightning.isEmpty {
            print("Bitcoin URI contains Lightning parameter - treating as Lightning payment")
            print("Parsed Lightning URI - Invoice: \(lightning)")
            
            let uriData: [String: Any] = [
                "type": "lightning",
                "invoice": lightning
            ]
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "handleLightningURI"), object: nil, userInfo: uriData) as Notification)
            }
            return
        }
        
        print("Parsed Bitcoin URI - Address: \(address), Amount: \(amount ?? "none"), Label: \(label ?? "none")")
        
        let uriData: [String: Any] = [
            "type": "bitcoin",
            "address": address,
            "amount": amount ?? "",
            "label": label ?? ""
        ]
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "handleBitcoinURI"), object: nil, userInfo: uriData) as Notification)
        }
    }
    
    private func handleLightningURI(_ url: URL) {
        print("Received Lightning URI: \(url.absoluteString)")
        
        // Parse Lightning URI: lightning:lnbc1... or lightning:user@domain.com
        // Extract invoice from the URL - it's everything after "lightning:"
        let urlString = url.absoluteString
        let invoice: String
        
        if let questionMarkIndex = urlString.firstIndex(of: "?") {
            // Extract invoice (everything between "lightning:" and "?")
            let invoiceStart = urlString.index(urlString.startIndex, offsetBy: 10) // Skip "lightning:"
            invoice = String(urlString[invoiceStart..<questionMarkIndex])
        } else {
            // No query parameters, invoice is everything after "lightning:"
            let invoiceStart = urlString.index(urlString.startIndex, offsetBy: 10) // Skip "lightning:"
            invoice = String(urlString[invoiceStart...])
        }
        
        print("Parsed Lightning URI - Invoice: \(invoice)")
        
        let uriData: [String: Any] = [
            "type": "lightning",
            "invoice": invoice
        ]
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "handleLightningURI"), object: nil, userInfo: uriData) as Notification)
        }
    }
    
    private func launchBittrValue(urlContexts: Set<UIOpenURLContext>, delay:Double) {
        
        guard let _: UIOpenURLContext = urlContexts.first(where: { $0.url.scheme == "widget-deeplink" }) else { return }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "openvalue"), object: nil, userInfo: nil) as Notification)
        }
    }


}

