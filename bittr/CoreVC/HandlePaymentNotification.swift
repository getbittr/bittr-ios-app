//
//  HandlePaymentNotification.swift
//  bittr
//
//  Created by Tom Melters on 08/02/2024.
//

import UIKit
import LDKNode
import LDKNodeFFI
import LightningDevKit

extension CoreViewController {
    
    @objc func handlePaymentNotification(notification:NSNotification) {
        
        if let userInfo = notification.userInfo as [AnyHashable:Any]? {
            
            // Check for the special key that indicates this is a silent notification.
            if let specialData = userInfo["bittr_specific_data"] as? [String: Any] {
                print("Received special data: \(specialData)")
                
                if self.didBecomeVisible == true {
                    // User has signed in.
                    
                    if self.wasNotified == false {
                        
                        let alert = UIAlertController(title: "Bittr payout", message: "You're receiving a new Lightning payment! Tap Okay to receive it now and continue what you're doing after.", preferredStyle: .alert)
                        alert.addAction(UIAlertAction(title: "Okay", style: .cancel, handler: { _ in
                            self.pendingLabel.text = "receiving payment"
                            self.pendingSpinner.startAnimating()
                            self.pendingView.alpha = 1
                            self.blackSignupBackground.alpha = 0.2
                            
                            self.varSpecialData = specialData
                            self.facilitateNotificationPayout(specialData: specialData)
                            self.needsToHandleNotification = false
                        }))
                        self.present(alert, animated: true)
                    } else {
                        self.pendingLabel.text = "receiving payment"
                        self.pendingSpinner.startAnimating()
                        self.pendingView.alpha = 1
                        self.blackSignupBackground.alpha = 0.2
                        
                        self.varSpecialData = specialData
                        self.facilitateNotificationPayout(specialData: specialData)
                        self.needsToHandleNotification = false
                    }
                } else {
                    // User hasn't signed in yet.
                    self.needsToHandleNotification = true
                    self.wasNotified = true
                    self.lightningNotification = notification
                    
                    let alert = UIAlertController(title: "Bittr payout", message: "Please sign in and wait a moment to receive your Lightning payment.", preferredStyle: .alert)
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
        
        let nodeIds = ["026d74bf2a035b8a14ea7c59f6a0698d019720e812421ec02762fdbf064c3bc326", "036956f49ef3db863e6f4dc34f24ace19be177168a0870e83fcaf6e7a683832b12"]
        let nodeId = nodeIds[UserDefaults.standard.value(forKey: "envkey") as? Int ?? 1] // Extract this from your peer string
        
        print("Did start payout process.")
        
        // Extract required data from specialData
        if let notificationId = specialData["notification_id"] as? String {
            let bitcoinAmountString = specialData["bitcoin_amount"] as? String ?? "0"
            let bitcoinAmount = Double(bitcoinAmountString) ?? 0.0
            let amountMsat = UInt64(bitcoinAmount * 100_000_000_000)
            
            let pubkey = LightningNodeService.shared.nodeId()
            print("Did get public key.")

            // Call payoutLightning in an async context
            Task.init {
                
                let peers = try await LightningNodeService.shared.listPeers()
                print("Did list peers.")
                if peers.count == 0 {
                    DispatchQueue.main.async {
                        self.pendingSpinner.stopAnimating()
                        self.pendingView.alpha = 0
                        self.blackSignupBackground.alpha = 0
                        let alert = UIAlertController(title: "Bittr payout", message: "We couldn't connect to Bittr. Please try again.", preferredStyle: .alert)
                        alert.addAction(UIAlertAction(title: "Close", style: .cancel, handler: nil))
                        alert.addAction(UIAlertAction(title: "Try again", style: .default, handler: {_ in
                            self.reconnectToPeer()
                        }))
                        self.present(alert, animated: true)
                    }
                } else if peers[0].nodeId == nodeId, peers[0].isConnected == false {
                    DispatchQueue.main.async {
                        self.pendingSpinner.stopAnimating()
                        self.pendingView.alpha = 0
                        self.blackSignupBackground.alpha = 0
                        let alert = UIAlertController(title: "Bittr payout", message: "We couldn't connect to Bittr. Please try again.", preferredStyle: .alert)
                        alert.addAction(UIAlertAction(title: "Close", style: .cancel, handler: nil))
                        alert.addAction(UIAlertAction(title: "Try again", style: .default, handler: {_ in
                            self.reconnectToPeer()
                        }))
                        self.present(alert, animated: true)
                    }
                } else {
                    let invoice = try await LightningNodeService.shared.receivePayment(
                        amountMsat: amountMsat,
                        description: notificationId,
                        expirySecs: 3600
                    )
                    print("Did create invoice.")
                    
                    DispatchQueue.main.async {
                        let invoiceHash = self.getInvoiceHash(invoiceString: invoice)
                        let newTimestamp = Int(Date().timeIntervalSince1970)
                        CacheManager.storeInvoiceTimestamp(hash: invoiceHash, timestamp: newTimestamp)
                        CacheManager.storeInvoiceDescription(hash: invoiceHash, desc: notificationId)
                        print("Did cache invoice data.")
                    }
                    
                    let lightningSignature = try await LightningNodeService.shared.signMessage(message: notificationId)
                    print("Did sign message.")
                    
                    do {
                        let payoutResponse = try await BittrService.shared.payoutLightning(notificationId: notificationId, invoice: invoice, signature: lightningSignature, pubkey: pubkey)
                        print("Payout successful. PreImage: \(payoutResponse.preImage ?? "N/A")")
                        //completionHandler(.newData)
                        
                        DispatchQueue.main.async {
                            
                            let receivedTransaction = Transaction()
                            receivedTransaction.received = Int(amountMsat)/1000
                            receivedTransaction.sent = 0
                            receivedTransaction.isLightning = true
                            receivedTransaction.isBittr = false
                            receivedTransaction.lnDescription = notificationId
                            receivedTransaction.timestamp = Int(Date().timeIntervalSince1970)
                            
                            self.receivedBittrTransaction = receivedTransaction
                            
                            self.pendingSpinner.stopAnimating()
                            self.pendingView.alpha = 0
                            self.blackSignupBackground.alpha = 0
                            self.performSegue(withIdentifier: "CoreToLightning", sender: self)
                        }
                    } catch {
                        print("Error occurred: \(error.localizedDescription)")
                        DispatchQueue.main.async {
                            self.pendingSpinner.stopAnimating()
                            self.pendingView.alpha = 0
                            self.blackSignupBackground.alpha = 0
                            let alert = UIAlertController(title: "Bittr payout", message: "\(error.localizedDescription)", preferredStyle: .alert)
                            if error.localizedDescription.contains("try again") {
                                alert.addAction(UIAlertAction(title: "Try again", style: .default, handler: {_ in
                                    if let actualSpecialData = self.varSpecialData {
                                        self.facilitateNotificationPayout(specialData: actualSpecialData)
                                    }
                                }))
                            }
                            alert.addAction(UIAlertAction(title: "Close", style: .cancel, handler: nil))
                            self.present(alert, animated: true)
                        }
                    }
                }
            }
        } else {
            print("Required data not found in notification.")
            self.pendingSpinner.stopAnimating()
            self.pendingView.alpha = 0
            self.blackSignupBackground.alpha = 0
            let alert = UIAlertController(title: "Bittr payout", message: "The notification payload did not contain the data needed to complete your payout.", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Close", style: .cancel, handler: nil))
            self.present(alert, animated: true)
        }
    }
    
    func getInvoiceHash(invoiceString:String) -> String {
        
        let result = Bolt11Invoice.fromStr(s: invoiceString)
        //let result = Bolt11Invoice(stringLiteral: invoiceString)
        if result.isOk() {
            if let invoice = result.getValue() {
                print("Invoice parsed successfully: \(invoice)")
                let paymentHash:[UInt8] = invoice.paymentHash()!
                let hexString = paymentHash.map { String(format: "%02x", $0) }.joined()
                return hexString
            } else {
                return "empty"
            }
        } else if let error = result.getError() {
            print("Failed to parse invoice: \(error)")
            return "empty"
        } else {
            return "empty"
        }
    }
    
    func reconnectToPeer() {
        
        // .testnet and .bitcoin
        let nodeIds = ["026d74bf2a035b8a14ea7c59f6a0698d019720e812421ec02762fdbf064c3bc326", "036956f49ef3db863e6f4dc34f24ace19be177168a0870e83fcaf6e7a683832b12"]
        let addresses = ["109.205.181.232:9735", "86.104.228.24:9735"]
        
        // Connect to Lightning peer.
        let nodeId = nodeIds[UserDefaults.standard.value(forKey: "envkey") as? Int ?? 1] // Extract this from your peer string
        let address = addresses[UserDefaults.standard.value(forKey: "envkey") as? Int ?? 1] // Extract this from your peer string
        
        let connectTask = Task {
            do {
                try await LightningNodeService.shared.connect(
                    nodeId: nodeId,
                    address: address,
                    persist: true
                )
                try Task.checkCancellation()
                if Task.isCancelled == true {
                    print("Did connect to peer, but too late.")
                    return false
                }
                print("Did connect to peer.")
                return true
                //self.getChannelsAndPayments(actualWalletTransactions: self.varWalletTransactions)
            } catch let error as NodeError {
                let errorString = handleNodeError(error)
                DispatchQueue.main.async {
                    // Handle UI error showing here, like showing an alert
                    print("Can't connect to peer: \(errorString)")
                    //self.getChannelsAndPayments(actualWalletTransactions: self.varWalletTransactions)
                }
                return false
            } catch {
                DispatchQueue.main.async {
                    // Handle UI error showing here, like showing an alert
                    print("Can't connect to peer: No error message.")
                    //self.getChannelsAndPayments(actualWalletTransactions: self.varWalletTransactions)
                }
                return false
            }
        }
        
        let timeoutTask = Task {
            try await Task.sleep(nanoseconds: UInt64(5) * NSEC_PER_SEC)
            connectTask.cancel()
            print("Connecting to peer takes too long.")
            if let actualSpecialData = self.varSpecialData {
                self.facilitateNotificationPayout(specialData: actualSpecialData)
            }
        }
        
        Task.init {
            let result = await connectTask.value
            timeoutTask.cancel()
            if let actualSpecialData = self.varSpecialData {
                self.facilitateNotificationPayout(specialData: actualSpecialData)
            }
        }
    }

}
