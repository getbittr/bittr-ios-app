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
import Sentry

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
            }
        }
    }
    
    
    func facilitateNotificationPayout(specialData:[String:Any]) {
        
        // TODO: Public?
        let nodeIds = ["026d74bf2a035b8a14ea7c59f6a0698d019720e812421ec02762fdbf064c3bc326", "036956f49ef3db863e6f4dc34f24ace19be177168a0870e83fcaf6e7a683832b12"]
        let nodeId = nodeIds[UserDefaults.standard.value(forKey: "envkey") as? Int ?? 1]
        
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
                    
                    do {
                        let invoice = try await LightningNodeService.shared.receivePayment(
                            amountMsat: amountMsat,
                            description: notificationId,
                            expirySecs: 3600
                        )
                        print("Did create invoice.")
                        
                        DispatchQueue.main.async {
                            if let invoiceHash = self.getInvoiceHash(invoiceString: invoice) {
                                let newTimestamp = Int(Date().timeIntervalSince1970)
                                CacheManager.storeInvoiceTimestamp(hash: invoiceHash, timestamp: newTimestamp)
                                CacheManager.storeInvoiceDescription(hash: invoiceHash, desc: notificationId)
                                print("Did cache invoice data.")
                            }
                        }
                        
                        let lightningSignature = try await LightningNodeService.shared.signMessage(message: notificationId)
                        print("Did sign message.")
                        
                        let payoutResponse = try await BittrService.shared.payoutLightning(notificationId: notificationId, invoice: invoice, signature: lightningSignature, pubkey: pubkey)
                        print("Payout successful. PreImage: \(payoutResponse.preImage ?? "N/A")")
                        
                        DispatchQueue.main.async {
                            
                            let receivedTransaction = Transaction()
                            receivedTransaction.received = Int(amountMsat)/1000
                            receivedTransaction.sent = 0
                            receivedTransaction.isLightning = true
                            receivedTransaction.isBittr = true
                            receivedTransaction.lnDescription = notificationId
                            receivedTransaction.timestamp = Int(Date().timeIntervalSince1970)
                            receivedTransaction.id = payoutResponse.preImage ?? "Unavailable"
                            
                            self.receivedBittrTransaction = receivedTransaction
                            
                            self.pendingSpinner.stopAnimating()
                            self.pendingView.alpha = 0
                            self.blackSignupBackground.alpha = 0
                            
                            if let actualHomeVC = self.homeVC {
                                actualHomeVC.setTransactions += [receivedTransaction]
                                actualHomeVC.setTransactions.sort { transaction1, transaction2 in
                                    transaction1.timestamp > transaction2.timestamp
                                }
                                actualHomeVC.homeTableView.reloadData()
                            }
                            
                            self.performSegue(withIdentifier: "CoreToLightning", sender: self)
                        }
                    } catch {
                        print("Error occurred: \(error.localizedDescription)")
                        DispatchQueue.main.async {
                            SentrySDK.capture(error: error)
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
    
    func getInvoiceHash(invoiceString:String) -> String? {
        
        let result = Bolt11Invoice.fromStr(s: invoiceString)
        if result.isOk() {
            if let invoice = result.getValue() {
                print("Invoice parsed successfully: \(invoice)")
                let paymentHash:[UInt8] = invoice.paymentHash()!
                let hexString = paymentHash.map { String(format: "%02x", $0) }.joined()
                return hexString
            } else {
                return nil
            }
        } else if let error = result.getError() {
            print("Failed to parse invoice: \(error)")
            return nil
        } else {
            return nil
        }
    }
    
    func reconnectToPeer() {
        
        // TODO: Public?
        // .testnet and .bitcoin
        let nodeIds = ["03c94d19734a7808a333bba797a6ffe30a745609d7cd049cf4f5e4685e85ca6f36", "036956f49ef3db863e6f4dc34f24ace19be177168a0870e83fcaf6e7a683832b12"]
        let addresses = ["109.205.181.232:29735", "86.104.228.24:9735"]
        
        // Connect to Lightning peer.
        let nodeId = nodeIds[UserDefaults.standard.value(forKey: "envkey") as? Int ?? 1]
        let address = addresses[UserDefaults.standard.value(forKey: "envkey") as? Int ?? 1]
        
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
            } catch let error as NodeError {
                let errorString = handleNodeError(error)
                DispatchQueue.main.async {
                    // Handle UI error showing here, like showing an alert
                    print("Can't connect to peer: \(errorString)")
                    SentrySDK.capture(error: error)
                }
                return false
            } catch {
                DispatchQueue.main.async {
                    // Handle UI error showing here, like showing an alert
                    print("Can't connect to peer: No error message.")
                    SentrySDK.capture(error: error)
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
    
    @objc func ldkEventReceived(notification:NSNotification) {
        
        if let userInfo = notification.userInfo as [AnyHashable:Any]? {
            // Check for the event information.
            if let event = userInfo["event"] as? LDKNode.Event {
                print("Event found. \(event)")
                
                // Examples of receivable event notifications:
                
                // channelPending(channelId: "7bfbba3e920032e2ade75c87fded2df355eed02e0acf6c33e429074c1327118a", userChannelId: "59143365509798668266523725445259806253", formerTemporaryChannelId: "89797af9337335cd2400bdc1e37d1abefc114081fa7912e4e780b3d13254768d", counterpartyNodeId: "036956f49ef3db863e6f4dc34f24ace19be177168a0870e83fcaf6e7a683832b12", fundingTxo: LDKNode.OutPoint(txid: "8a1127134c0729e4336ccf0a2ed0ee55f32dedfd875ce7ade23200923ebafb7b", vout: 0))
                
                // channelReady(channelId: "7bfbba3e920032e2ade75c87fded2df355eed02e0acf6c33e429074c1327118a", userChannelId: "59143365509798668266523725445259806253", counterpartyNodeId: Optional("036956f49ef3db863e6f4dc34f24ace19be177168a0870e83fcaf6e7a683832b12"))
                
                // paymentReceived(paymentHash: "3ca1c72b360d1d1124ff0e9dafcce7165b79c342d0f159ac431088b8c5487d6c", amountMsat: 30745000)
                
                // channelClosed(channelId: "df5d5b9b7d10c4e12bb01f50a8fcffc6112b612dcbecdbcf65bb3fea8b89ee32", userChannelId: "46771750509148822319613831140583118455", counterpartyNodeId: Optional("036956f49ef3db863e6f4dc34f24ace19be177168a0870e83fcaf6e7a683832b12"))
                
                if CacheManager.hasHandledEvent(event: "\(event)") {
                    // Event has already been handled.
                    print("Event was handled before.")
                    return
                } else if "\(event)".contains("paymentReceived") {
                    
                    if let actualSpecialData = self.varSpecialData {
                        // This is a Bittr payment, which is being handled separately.
                        CacheManager.didHandleEvent(event: "\(event)")
                        return
                    }
                    
                    let paymentHash = "\(event)".split(separator: ",")[1].replacingOccurrences(of: "\"", with: "").replacingOccurrences(of: " paymentHash: ", with: "")
                    print("Did extract payment hash: \(paymentHash).")
                    
                    if let paymentDetails = LightningNodeService.shared.getPaymentDetails(paymentHash: paymentHash) {
                        
                        print("Did receive payment details.")
                        
                        let thisTransaction = Transaction()
                        thisTransaction.isBittr = false
                        thisTransaction.isLightning = true
                        thisTransaction.id = paymentDetails.id
                        thisTransaction.sent = 0
                        thisTransaction.received = Int(paymentDetails.amountMsat ?? 0)/1000
                        thisTransaction.timestamp = Int(Date().timeIntervalSince1970)
                        thisTransaction.confirmations = 0
                        thisTransaction.height = 0
                        thisTransaction.fee = 0
                        
                        self.receivedBittrTransaction = thisTransaction
                        DispatchQueue.main.async {
                            CacheManager.didHandleEvent(event: "\(event)")
                            
                            if let actualHomeVC = self.homeVC {
                                actualHomeVC.setTransactions += [thisTransaction]
                                actualHomeVC.setTransactions.sort { transaction1, transaction2 in
                                    transaction1.timestamp > transaction2.timestamp
                                }
                                actualHomeVC.homeTableView.reloadData()
                            }
                            
                            self.performSegue(withIdentifier: "CoreToLightning", sender: self)
                        }
                    }
                } else if "\(event)".contains("channelClosed") {
                    
                    DispatchQueue.main.async {
                        
                        CacheManager.didHandleEvent(event: "\(event)")
                        let notificationDict:[String: Any] = ["question":"closed lightning channel","answer":"We've been notified that your lightning channel has been closed.\n\nAny funds that were in this channel will be deposited into your bitcoin wallet.\n\nTo open a channel with Bittr, buy bitcoin worth up to 100 Swiss Francs or Euros. Check your wallet's Buy section or getbittr.com for all information."]
                        NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "question"), object: nil, userInfo: notificationDict) as Notification)
                    }
                } else if "\(event)".contains("channelPending") {
                    
                    CacheManager.didHandleEvent(event: "\(event)")
                    
                    let fundingTxo = "\(event)".split(separator: ",")[4].replacingOccurrences(of: "\"", with: "").replacingOccurrences(of: " fundingTxo: LDKNode.OutPoint(txid: ", with: "")
                    var depositCodes = [String]()
                    for eachIbanEntity in self.client.ibanEntities {
                        if eachIbanEntity.yourUniqueCode != "" {
                            depositCodes += [eachIbanEntity.yourUniqueCode]
                        }
                    }
                    
                    DispatchQueue.global(qos: .background).asyncAfter(deadline: .now() + 3) {
                        print("Did wait to start API call.")
                        
                        Task {
                            do {
                                let bittrApiTransactions = try await BittrService.shared.fetchBittrTransactions(txIds: [fundingTxo], depositCodes: depositCodes)
                                print("Bittr transactions: \(bittrApiTransactions.count)")
                                
                                if bittrApiTransactions.count == 1 {
                                    for eachTransaction in bittrApiTransactions {
                                        if eachTransaction.txId == fundingTxo {
                                            
                                            // This is the funding Txo.
                                            let formatter = DateFormatter()
                                            formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS"
                                            let transactionDate = formatter.date(from:eachTransaction.datetime)!
                                            let transactionTimestamp = Int(transactionDate.timeIntervalSince1970)
                                            
                                            let thisTransaction = Transaction()
                                            thisTransaction.isBittr = true
                                            thisTransaction.isLightning = true
                                            thisTransaction.purchaseAmount = Int(CGFloat(truncating: NumberFormatter().number(from: (eachTransaction.purchaseAmount).replacingOccurrences(of: ".", with: Locale.current.decimalSeparator!).replacingOccurrences(of: ",", with: Locale.current.decimalSeparator!))!))
                                            thisTransaction.currency = eachTransaction.currency
                                            thisTransaction.id = eachTransaction.txId
                                            thisTransaction.sent = 0
                                            thisTransaction.received = Int(CGFloat(truncating: NumberFormatter().number(from: (eachTransaction.bitcoinAmount).replacingOccurrences(of: ".", with: Locale.current.decimalSeparator!).replacingOccurrences(of: ",", with: Locale.current.decimalSeparator!))!)*100000000)
                                            thisTransaction.timestamp = transactionTimestamp
                                            thisTransaction.lnDescription = CacheManager.getInvoiceDescription(hash: eachTransaction.txId)
                                            thisTransaction.isFundingTransaction = true
                                            
                                            self.receivedBittrTransaction = thisTransaction
                                            
                                            DispatchQueue.main.async {
                                                if let actualHomeVC = self.homeVC {
                                                    actualHomeVC.setTransactions += [thisTransaction]
                                                    actualHomeVC.setTransactions.sort { transaction1, transaction2 in
                                                        transaction1.timestamp > transaction2.timestamp
                                                    }
                                                    actualHomeVC.homeTableView.reloadData()
                                                }
                                                
                                                self.performSegue(withIdentifier: "CoreToLightning", sender: self)
                                            }
                                        }
                                    }
                                }
                            } catch {
                                print("Bittr error: \(error.localizedDescription)")
                            }
                        }
                    }
                }
                
            } else {
                print("No event.")
            }
        }
    }

}
