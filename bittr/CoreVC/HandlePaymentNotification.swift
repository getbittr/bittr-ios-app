//
//  HandlePaymentNotification.swift
//  bittr
//
//  Created by Tom Melters on 08/02/2024.
//

import UIKit

extension CoreViewController {

    
    @objc func handlePaymentNotification(notification:NSNotification) {
        
        if let userInfo = notification.userInfo as [AnyHashable:Any]? {
            
            // Check for the special key that indicates this is a silent notification.
            if let specialData = userInfo["bittr_specific_data"] as? [String: Any] {
                print("Received special data: \(specialData)")
                
                if self.didBecomeVisible == true {
                    // User has signed in.
                    
                    self.pendingSpinner.startAnimating()
                    self.pendingView.alpha = 1
                    self.blackSignupBackground.alpha = 0.2
                    
                    self.facilitateNotificationPayout(specialData: specialData)
                    self.needsToHandleNotification = false
                } else {
                    // User hasn't signed in yet.
                    self.needsToHandleNotification = true
                    self.lightningNotification = notification
                    
                    let alert = UIAlertController(title: "Lightning payment", message: "Please sign in and wait a moment to receive your Lightning payment.", preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: "Okay", style: .cancel, handler: nil))
                    self.present(alert, animated: true)
                }
            } else {
                // No special key, so this is a normal notification.
                print("No special key found in notification.")
                //completionHandler(.noData)
            }
        }
    }
    
    
    func facilitateNotificationPayout(specialData:[String:Any]) {
        
        // Extract required data from specialData
        if let notificationId = specialData["notification_id"] as? String {
            let bitcoinAmountString = specialData["bitcoin_amount"] as? String ?? "0"
            let bitcoinAmount = Double(bitcoinAmountString) ?? 0.0
            let amountMsat = UInt64(bitcoinAmount * 100_000_000_000)
            
            
            
            let pubkey = LightningNodeService.shared.nodeId()

            
            // Call payoutLightning in an async context
            Task.init {
                
                let peers = try await LightningNodeService.shared.listPeers()
                if peers.count == 0 {
                    DispatchQueue.main.async {
                        self.pendingSpinner.stopAnimating()
                        self.pendingView.alpha = 0
                        self.blackSignupBackground.alpha = 0
                        let alert = UIAlertController(title: "Lightning payment", message: "Not connected to any peers. [1]", preferredStyle: .alert)
                        alert.addAction(UIAlertAction(title: "Okay", style: .cancel, handler: nil))
                        self.present(alert, animated: true)
                    }
                } else if peers[0].nodeId == "026d74bf2a035b8a14ea7c59f6a0698d019720e812421ec02762fdbf064c3bc326", peers[0].isConnected == false {
                    DispatchQueue.main.async {
                        self.pendingSpinner.stopAnimating()
                        self.pendingView.alpha = 0
                        self.blackSignupBackground.alpha = 0
                        let alert = UIAlertController(title: "Lightning payment", message: "Not connected to any peers. [2]", preferredStyle: .alert)
                        alert.addAction(UIAlertAction(title: "Okay", style: .cancel, handler: nil))
                        self.present(alert, animated: true)
                    }
                }
                
                let invoice = try await LightningNodeService.shared.receivePayment(
                    amountMsat: amountMsat,
                    description: notificationId,
                    expirySecs: 3600
                )
                
                DispatchQueue.main.async {
                    let invoiceHash = LightningNodeService.shared.getInvoiceHash(invoiceString: invoice)
                    let newTimestamp = Int(Date().timeIntervalSince1970)
                    CacheManager.storeInvoiceTimestamp(hash: invoiceHash, timestamp: newTimestamp)
                    CacheManager.storeInvoiceDescription(hash: invoiceHash, desc: notificationId)
                }
                
                let lightningSignature = try await LightningNodeService.shared.signMessage(message: notificationId)
                
                do {
                    let payoutResponse = try await BittrService.shared.payoutLightning(notificationId: notificationId, invoice: invoice, signature: lightningSignature, pubkey: pubkey)
                    print("Payout successful. PreImage: \(payoutResponse.preImage ?? "N/A")")
                    //completionHandler(.newData)
                    
                    DispatchQueue.main.async {
                        self.pendingSpinner.stopAnimating()
                        self.pendingView.alpha = 0
                        self.blackSignupBackground.alpha = 0
                        self.performSegue(withIdentifier: "CoreToLightning", sender: self)
                    }
                } catch {
                    print("Error occurred: \(error.localizedDescription)")
                    //completionHandler(.failed)
                }
            }
        } else {
            print("Required data not found in notification.")
            //completionHandler(.noData)
        }
    }

}
