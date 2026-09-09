//
//  URIs.swift
//  bittr
//
//  Created by Tom Melters on 12/10/25.
//

import UIKit

extension CoreViewController {
    
    func needsToHandleURI() -> Bool {
        
        if let bitcoinData = UserDefaults.standard.object(forKey: "pendingBitcoinURI") as? [String: Any],
           let _ = bitcoinData["address"] as? String,
           let _ = bitcoinData["amount"] as? String,
           let _ = bitcoinData["label"] as? String {
            // There's a Bitcoin URI.
            return true
        } else if let lightningData = UserDefaults.standard.object(forKey: "pendingLightningURI") as? [String: Any],
           let _ = lightningData["invoice"] as? String {
            // There's a Lightning URI.
            return true
        } else {
            return false
        }
    }
    
    func checkForPendingURIs() {
        
        // Check for pending Bitcoin URI
        if let bitcoinData = UserDefaults.standard.object(forKey: "pendingBitcoinURI") as? [String: Any],
           let address = bitcoinData["address"] as? String,
           let amount = bitcoinData["amount"] as? String,
           let label = bitcoinData["label"] as? String {
            
            UserDefaults.standard.removeObject(forKey: "pendingBitcoinURI")
            self.navigateToSendScreenWithBitcoinURI(address: address, amount: amount, label: label)
            return
        }
        
        // Check for pending Lightning URI
        if let lightningData = UserDefaults.standard.object(forKey: "pendingLightningURI") as? [String: Any],
           let invoice = lightningData["invoice"] as? String {
            
            UserDefaults.standard.removeObject(forKey: "pendingLightningURI")
            self.navigateToSendScreenWithLightningURI(invoice: invoice)
            return
        }
    }
    
    private func navigateToSendScreenWithBitcoinURI(address: String, amount: String, label: String) {
        
        // Navigate to send screen via HomeViewController
        if let homeVC = self.homeVC {
            // Check if there's already a send screen open and dismiss it first
            if let existingSendVC = homeVC.presentedViewController {
                Log.info("Dismissing existing send screen before opening new one")
                existingSendVC.dismiss(animated: false) {
                    // After dismissing, open the new send screen
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        self.openNewSendScreenWithBitcoinURI(homeVC: homeVC, address: address, amount: amount, label: label)
                    }
                }
            } else {
                // No existing send screen, open directly
                self.openNewSendScreenWithBitcoinURI(homeVC: homeVC, address: address, amount: amount, label: label)
            }
        }
    }
    
    private func openNewSendScreenWithBitcoinURI(homeVC: HomeViewController, address: String, amount: String, label: String) {
        // Store the URI data in HomeViewController so it can be passed during segue
        homeVC.pendingBitcoinURI = (address: address, amount: amount, label: label)
        homeVC.performSegue(withIdentifier: "HomeToSend", sender: homeVC)
    }
    
    private func navigateToSendScreenWithLightningURI(invoice: String) {
        
        // Navigate to send screen via HomeViewController
        if let homeVC = self.homeVC {
            // Check if there's already a send screen open and dismiss it first
            if let existingSendVC = homeVC.presentedViewController {
                Log.info("Dismissing existing send screen before opening new one")
                existingSendVC.dismiss(animated: false) {
                    // After dismissing, open the new send screen
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        self.openNewSendScreenWithLightningURI(homeVC: homeVC, invoice: invoice)
                    }
                }
            } else {
                // No existing send screen, open directly
                self.openNewSendScreenWithLightningURI(homeVC: homeVC, invoice: invoice)
            }
        }
    }
    
    private func openNewSendScreenWithLightningURI(homeVC: HomeViewController, invoice: String) {
        // Store the URI data in HomeViewController so it can be passed during segue
        homeVC.pendingLightningURI = invoice
        homeVC.performSegue(withIdentifier: "HomeToSend", sender: homeVC)
    }
    
    @objc func handleBitcoinURI(notification: NSNotification) {
        
        guard let userInfo = notification.userInfo as? [String: Any],
              let address = userInfo["address"] as? String,
              !address.isEmpty else {
            Log.info("Invalid Bitcoin URI data")
            return
        }
        
        let amount = userInfo["amount"] as? String ?? ""
        let label = userInfo["label"] as? String ?? ""
        
        Log.info("Handling Bitcoin URI.")
        Log.debug("Handling Bitcoin URI - Address: \(address), Amount: \(amount), Label: \(label)")
        
        // Check if user is signed in
        DispatchQueue.main.async {
            if self.userHasSignedIn {
                // User is signed in, navigate to send screen immediately
                self.navigateToSendScreenWithBitcoinURI(address: address, amount: amount, label: label)
            } else {
                // User hasn't signed in yet, store URI data for later
                self.storeBitcoinURIData(address: address, amount: amount, label: label)
                self.showAlert(title: Language.getWord(withID: "sendbitcoin"), message: Language.getWord(withID: "pleasesignintosend"), buttons: [.dismiss(Language.getWord(withID: "okay"))])
            }
        }
    }
    
    @objc func handleLightningURI(notification: NSNotification) {
        
        guard let userInfo = notification.userInfo as? [String: Any],
              let invoice = userInfo["invoice"] as? String,
              !invoice.isEmpty else {
            Log.info("Invalid Lightning URI data")
            return
        }
        
        Log.info("Handling Lightning URI.")
        Log.debug("Handling Lightning URI - Invoice: \(invoice)")
        
        // Check if user is signed in
        DispatchQueue.main.async {
            if self.userHasSignedIn {
                // User is signed in, navigate to send screen immediately
                self.navigateToSendScreenWithLightningURI(invoice: invoice)
            } else {
                // User hasn't signed in yet, store URI data for later
                self.storeLightningURIData(invoice: invoice)
                self.showAlert(title: Language.getWord(withID: "sendbitcoin"), message: Language.getWord(withID: "pleasesignintosend"), buttons: [.dismiss(Language.getWord(withID: "okay"))])
            }
        }
    }
    
    private func storeBitcoinURIData(address: String, amount: String, label: String) {
        
        let uriData: [String: Any] = [
            "type": "bitcoin",
            "address": address,
            "amount": amount,
            "label": label
        ]
        
        UserDefaults.standard.set(uriData, forKey: "pendingBitcoinURI")
    }
    
    private func storeLightningURIData(invoice: String) {
        
        let uriData: [String: Any] = [
            "type": "lightning",
            "invoice": invoice
        ]
        
        UserDefaults.standard.set(uriData, forKey: "pendingLightningURI")
    }
}
