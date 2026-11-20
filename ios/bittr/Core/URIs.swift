//
//  URIs.swift
//  bittr
//
//  Created by Tom Melters on 12/10/25.
//

import UIKit

extension CoreViewController {
    
    // How long a payment URI that arrived before sign-in is kept.
    private static let pendingPaymentURILifetime:TimeInterval = 10 * 60
    
    func needsToHandleURI() -> Bool {
        self.pendingPaymentURI() != nil
    }
    
    func checkForPendingURIs() {
        
        // Check for a payment URI that arrived before sign-in.
        if let code = self.pendingPaymentURI() {
            self.removePendingPaymentURI()
            self.navigateToSendScreen(withPaymentURI: code)
        }
    }
    
    // The payment URI that arrived before sign-in, if it's recent enough to still be meant.
    private func pendingPaymentURI() -> String? {
        guard let code = UserDefaults.standard.string(forKey: "pendingPaymentURI") else { return nil }
        let storedAt = UserDefaults.standard.double(forKey: "pendingPaymentURIDate")
        guard Date().timeIntervalSince1970 - storedAt < Self.pendingPaymentURILifetime else {
            self.removePendingPaymentURI()
            return nil
        }
        return code
    }
    
    private func removePendingPaymentURI() {
        UserDefaults.standard.removeObject(forKey: "pendingPaymentURI")
        UserDefaults.standard.removeObject(forKey: "pendingPaymentURIDate")
        
        // Keys an earlier version used for the same purpose.
        UserDefaults.standard.removeObject(forKey: "pendingBitcoinURI")
        UserDefaults.standard.removeObject(forKey: "pendingLightningURI")
    }
    
    private func navigateToSendScreen(withPaymentURI code: String) {
        
        // Navigate to send screen via HomeViewController
        if let homeVC = self.homeVC {
            // Check if there's already a send screen open and dismiss it first
            if let existingSendVC = homeVC.presentedViewController {
                Log.info("Dismissing existing send screen before opening new one")
                existingSendVC.dismiss(animated: false) {
                    // After dismissing, open the new send screen
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        self.openNewSendScreen(homeVC: homeVC, paymentURI: code)
                    }
                }
            } else {
                // No existing send screen, open directly
                self.openNewSendScreen(homeVC: homeVC, paymentURI: code)
            }
        }
    }
    
    private func openNewSendScreen(homeVC: HomeViewController, paymentURI code: String) {
        // Store the URI in HomeViewController so it can be passed during segue
        homeVC.pendingPaymentURI = code
        homeVC.performSegue(withIdentifier: "HomeToSend", sender: homeVC)
    }
    
    @objc func handlePaymentURI(notification: NSNotification) {
        
        guard let code = notification.userInfo?["code"] as? String, !code.isEmpty else {
            Log.info("Invalid payment URI data")
            return
        }
        
        Log.info("Handling payment URI.")
        Log.debug("Handling payment URI: \(code)")
        
        // Check if user is signed in
        DispatchQueue.main.async {
            if self.userHasSignedIn {
                // User is signed in, navigate to send screen immediately
                self.navigateToSendScreen(withPaymentURI: code)
            } else {
                // User hasn't signed in yet, store the URI for later
                UserDefaults.standard.set(code, forKey: "pendingPaymentURI")
                UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "pendingPaymentURIDate")
                self.showAlert(title: Language.getWord(withID: "sendbitcoin"), message: Language.getWord(withID: "pleasesignintosend"), buttons: [.dismiss(Language.getWord(withID: "okay"))])
            }
        }
    }
}
