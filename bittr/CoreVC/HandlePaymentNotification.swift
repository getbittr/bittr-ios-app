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
                
                CacheManager.storeLatestNotification(specialData: specialData)
                
                if self.didBecomeVisible == true {
                    // User has signed in.
                    
                    if self.wasNotified == false {
                        // App was open when notification came in.
                        self.varSpecialData = specialData
                        self.showAlert(presentingController: self, title: Language.getWord(withID: "bittrpayout"), message: Language.getWord(withID: "newbittrpayment"), buttons: [Language.getWord(withID: "okay")], actions: [#selector(self.triggerPayout)])
                    } else {
                        // App was closed when notification came in and was subsequently opened.
                        self.pendingLabel.text = Language.getWord(withID: "receivingpayment")
                        self.pendingSpinner.startAnimating()
                        self.pendingView.alpha = 1
                        self.blackSignupBackground.alpha = 0.2
                        
                        self.varSpecialData = specialData
                        self.facilitateNotificationPayout()
                        self.needsToHandleNotification = false
                    }
                } else {
                    // User hasn't signed in yet.
                    self.needsToHandleNotification = true
                    self.wasNotified = true
                    self.lightningNotification = notification
                    
                    self.showAlert(presentingController: self, title: Language.getWord(withID: "bittrpayout"), message: Language.getWord(withID: "pleasesignin"), buttons: [Language.getWord(withID: "okay")], actions: nil)
                }
            } else {
                // No special key, so this is a normal notification.
                print("No special key found in notification.")
            }
        }
    }
    
    @objc func triggerPayout() {
        self.hideAlert()
        self.pendingLabel.text = Language.getWord(withID: "receivingpayment")
        self.pendingSpinner.startAnimating()
        self.pendingView.alpha = 1
        self.blackSignupBackground.alpha = 0.2
        self.facilitateNotificationPayout()
        self.needsToHandleNotification = false
    }
    
    
    @objc func facilitateNotificationPayout() {
        self.hideAlert()
        
        // TODO: Public?
        let nodeIds = ["03e46857c6c24302d7231ff42770728cc0f86296473d174f70cfca90b640dc2fd6", "03e46857c6c24302d7231ff42770728cc0f86296473d174f70cfca90b640dc2fd6"]
        let nodeId = nodeIds[UserDefaults.standard.value(forKey: "envkey") as? Int ?? 1]
        
        print("Did start payout process.")
        var specialData = [String:Any]()
        if self.varSpecialData != nil {
            specialData = self.varSpecialData!
        } else {
            print("No special data available.")
            return
        }
        
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
                        self.showAlert(presentingController: self, title: Language.getWord(withID: "bittrpayout"), message: Language.getWord(withID: "couldntconnect"), buttons: [Language.getWord(withID: "close"), Language.getWord(withID: "tryagain")], actions: [nil, #selector(self.reconnectToPeer)])
                    }
                } else if peers[0].nodeId == nodeId, peers[0].isConnected == false {
                    DispatchQueue.main.async {
                        self.pendingSpinner.stopAnimating()
                        self.pendingView.alpha = 0
                        self.blackSignupBackground.alpha = 0
                        self.showAlert(presentingController: self, title: Language.getWord(withID: "bittrpayout"), message: Language.getWord(withID: "couldntconnect"), buttons: [Language.getWord(withID: "close"), Language.getWord(withID: "tryagain")], actions: [nil, #selector(self.reconnectToPeer)])
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
                            if let invoiceHash = self.getInvoiceHash(invoiceString: invoice.description) {
                                let newTimestamp = Int(Date().timeIntervalSince1970)
                                CacheManager.storeInvoiceTimestamp(hash: invoiceHash, timestamp: newTimestamp)
                                CacheManager.storeInvoiceDescription(hash: invoiceHash, desc: notificationId)
                                print("Did cache invoice data.")
                            }
                        }
                        
                        let lightningSignature = try await LightningNodeService.shared.signMessage(message: notificationId)
                        print("Did sign message.")
                        
                        let payoutResponse = try await BittrService.shared.payoutLightning(notificationId: notificationId, invoice: invoice.description, signature: lightningSignature, pubkey: pubkey)
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
                            
                            self.addNewTransactionToHomeVC(newTransaction: receivedTransaction)
                            self.performSegue(withIdentifier: "CoreToLightning", sender: self)
                        }
                    } catch {
                        print("Error occurred: \(error.localizedDescription)")
                        DispatchQueue.main.async {
                            SentrySDK.capture(error: error)
                            self.pendingSpinner.stopAnimating()
                            self.pendingView.alpha = 0
                            self.blackSignupBackground.alpha = 0
                            if error.localizedDescription.contains("try again"), self.varSpecialData != nil {
                                self.showAlert(presentingController: self, title: Language.getWord(withID: "bittrpayout"), message: "\(error.localizedDescription)", buttons: [Language.getWord(withID: "close"), Language.getWord(withID: "tryagain")], actions: [nil, #selector(self.facilitateNotificationPayout)])
                            } else {
                                self.showAlert(presentingController: self, title: Language.getWord(withID: "bittrpayout"), message: "\(error.localizedDescription)", buttons: [Language.getWord(withID: "close")], actions: nil)
                            }
                        }
                    }
                }
            }
        } else {
            print("Required data not found in notification.")
            self.pendingSpinner.stopAnimating()
            self.pendingView.alpha = 0
            self.blackSignupBackground.alpha = 0
            self.showAlert(presentingController: self, title: Language.getWord(withID: "bittrpayout"), message: Language.getWord(withID: "bittrpayoutfail"), buttons: [Language.getWord(withID: "close")], actions: nil)
        }
    }
    
    
    @objc func reconnectToPeer() {
        self.hideAlert()
        
        // TODO: Public?
        // .testnet and .bitcoin
        let nodeIds = ["03e46857c6c24302d7231ff42770728cc0f86296473d174f70cfca90b640dc2fd6", "03e46857c6c24302d7231ff42770728cc0f86296473d174f70cfca90b640dc2fd6"]
        let addresses = ["31.58.51.17:9735", "31.58.51.17:9735"]
        
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
            if self.varSpecialData != nil {
                self.facilitateNotificationPayout()
            }
        }
        
        Task.init {
            let result = await connectTask.value
            timeoutTask.cancel()
            if self.varSpecialData != nil {
                self.facilitateNotificationPayout()
            }
        }
    }
    
    func ldkEventReceived(event:LDKNode.Event) {
        
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
        } else {
            switch event {
                
            case .paymentReceived(paymentId: let paymentId, paymentHash: let paymentHash, amountMsat: let amountMsat, customRecords: let customRecords):
                
                if self.varSpecialData != nil {
                    // This is a Bittr payment, which is being handled separately.
                    CacheManager.didHandleEvent(event: "\(event)")
                    return
                }
                
                if let paymentDetails = LightningNodeService.shared.getPaymentDetails(paymentHash: paymentHash) {
                    
                    print("Did receive payment details.")
                    
                    let thisTransaction = self.createTransaction(transactionDetails: nil, paymentDetails: paymentDetails, bittrTransaction: nil, swapTransaction: nil, coreVC: self, bittrTransactions: nil)
                    thisTransaction.isBittr = true
                    thisTransaction.timestamp = Int(Date().timeIntervalSince1970)
                    
                    if CacheManager.getInvoiceDescription(hash: paymentHash).contains("Swap onchain to lightning ") {
                        if self.homeVC != nil {
                            for (index, eachTransaction) in self.homeVC!.setTransactions.enumerated() {
                                if eachTransaction.lnDescription.contains("Swap onchain to lightning "), eachTransaction.lnDescription == CacheManager.getInvoiceDescription(hash: paymentHash) {
                                    // This is a swap. This is the matching onchain transaction.
                                    
                                    thisTransaction.isSwap = true
                                    thisTransaction.lightningID = thisTransaction.id
                                    thisTransaction.onchainID = eachTransaction.id
                                    thisTransaction.id = eachTransaction.lnDescription.replacingOccurrences(of: "Swap onchain to lightning ", with: "")
                                    thisTransaction.isBittr = false
                                    thisTransaction.lnDescription = CacheManager.getInvoiceDescription(hash: paymentHash)
                                    thisTransaction.boltzSwapId = CacheManager.getSwapID(dateID: thisTransaction.lnDescription) ?? "Unavailable"
                                    thisTransaction.isLightning = false
                                    thisTransaction.sent = eachTransaction.sent - eachTransaction.received
                                    thisTransaction.swapDirection = 0
                                    
                                    if let actualCurrentHeight = self.bittrWallet.currentHeight {
                                        thisTransaction.height = actualCurrentHeight
                                        thisTransaction.confirmations = 1
                                    }
                                    
                                    self.homeVC!.setTransactions.remove(at: index)
                                }
                            }
                        }
                    }
                    
                    self.receivedBittrTransaction = thisTransaction
                    DispatchQueue.main.async {
                        CacheManager.didHandleEvent(event: "\(event)")
                        self.addNewTransactionToHomeVC(newTransaction: thisTransaction)
                        if !thisTransaction.isSwap {
                            self.performSegue(withIdentifier: "CoreToLightning", sender: self)
                        }
                    }
                }
            case .channelClosed(channelId: let channelId, userChannelId: let userChannelId, counterpartyNodeId: let counterpartyNodeId, reason: let reason):
                
                DispatchQueue.main.async {
                    CacheManager.didHandleEvent(event: "\(event)")
                    self.launchQuestion(question: Language.getWord(withID: "closedlightningchannel"), answer: Language.getWord(withID: "closedlightningchannel2"), type: nil)
                }
            case .channelPending(channelId: let channelId, userChannelId: let userChannelId, formerTemporaryChannelId: let formerTemporaryChannelId, counterpartyNodeId: let counterpartyNodeId, fundingTxo: let fundingTxo):
                
                CacheManager.didHandleEvent(event: "\(event)")
                
                var depositCodes = [String]()
                for eachIbanEntity in self.bittrWallet.ibanEntities {
                    if eachIbanEntity.yourUniqueCode != "" {
                        depositCodes += [eachIbanEntity.yourUniqueCode]
                    }
                }
                
                DispatchQueue.global(qos: .background).asyncAfter(deadline: .now() + 3) {
                    print("Did wait to start API call.")
                    
                    Task {
                        do {
                            let bittrApiTransactions = try await BittrService.shared.fetchBittrTransactions(txIds: [fundingTxo.txid], depositCodes: depositCodes)
                            print("Bittr transactions: \(bittrApiTransactions.count)")
                            
                            if bittrApiTransactions.count == 1 {
                                for eachTransaction in bittrApiTransactions {
                                    if eachTransaction.txId == fundingTxo.txid {
                                        DispatchQueue.main.async {
                                            
                                            let thisTransaction = self.createTransaction(transactionDetails: nil, paymentDetails: nil, bittrTransaction: eachTransaction, swapTransaction: nil, coreVC: self.homeVC?.coreVC, bittrTransactions: self.homeVC?.bittrTransactions)
                                            
                                            self.receivedBittrTransaction = thisTransaction
                                            self.addNewTransactionToHomeVC(newTransaction: thisTransaction)
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
            case .paymentSuccessful(paymentId: let paymentId, paymentHash: let paymentHash, paymentPreimage: let paymentPreimage, feePaidMsat: let feePaidMsat):
                return
            case .paymentFailed(paymentId: let paymentId, paymentHash: let paymentHash, reason: let reason):
                return
            case .paymentClaimable(paymentId: let paymentId, paymentHash: let paymentHash, claimableAmountMsat: let claimableAmountMsat, claimDeadline: let claimDeadline, customRecords: let customRecords):
                return
            case .paymentForwarded(prevChannelId: let prevChannelId, nextChannelId: let nextChannelId, prevUserChannelId: let prevUserChannelId, nextUserChannelId: let nextUserChannelId, prevNodeId: let prevNodeId, nextNodeId: let nextNodeId, totalFeeEarnedMsat: let totalFeeEarnedMsat, skimmedFeeMsat: let skimmedFeeMsat, claimFromOnchainTx: let claimFromOnchainTx, outboundAmountForwardedMsat: let outboundAmountForwardedMsat):
                return
            case .channelReady(channelId: let channelId, userChannelId: let userChannelId, counterpartyNodeId: let counterpartyNodeId):
                return
            }
        }
    }
    
    func addNewTransactionToHomeVC(newTransaction:Transaction) {
        
        if self.homeVC != nil {
            
            // Add payment to HomeVC transactions table.
            self.homeVC!.setTransactions += [newTransaction]
            self.homeVC!.setTransactions.sort { transaction1, transaction2 in
                transaction1.timestamp > transaction2.timestamp
            }
            self.homeVC!.homeTableView.reloadData()
            
            // Update HomeVC balance.
            if newTransaction.isSwap {
                self.bittrWallet.satoshisLightning += (newTransaction.received - newTransaction.sent)
            } else {
                self.bittrWallet.satoshisLightning += newTransaction.received
            }
            self.homeVC!.setTotalSats(updateTableAfterConversion: false)
            
            // Add payment to channel details.
            self.bittrWallet.bittrChannel?.received += (newTransaction.received - newTransaction.sent)
        }
    }
    
        @objc func handleSwapNotificationFromBackground(notification: NSNotification) {
        // Prevent double handling
        if self.isHandlingSwapNotification {
            print("Already handling swap notification, skipping")
            return
        }
        
        if let userInfo = notification.userInfo as? [String: Any],
           let swapID = userInfo["swap_id"] as? String {
            
            print("Received swap notification from background for ID: \(swapID)")
            
            // Check if SwapViewController is already open - if so, ignore the notification
            if self.isSwapViewControllerOpen() {
                print("SwapViewController is already open, ignoring notification")
                return
            }
            
            // Set flag to prevent double handling
            self.isHandlingSwapNotification = true
            
            // Check if user is signed in (PIN has been entered)
            if self.didBecomeVisible == true {
                // User is signed in, handle notification immediately
                self.handleSwapNotificationImmediately(swapID: swapID, userInfo: userInfo)
            } else {
                // User hasn't signed in yet, store notification for later
                self.needsToHandleNotification = true
                self.wasNotified = true
                self.lightningNotification = notification
                
                // Reset the double handling flag since we're storing for later
                self.isHandlingSwapNotification = false
                
                self.showAlert(presentingController: self, title: Language.getWord(withID: "swapstatusupdate"), message: Language.getWord(withID: "pleasesignin"), buttons: [Language.getWord(withID: "okay")], actions: nil)
            }
        }
    }
    
    private func handleSwapNotificationImmediately(swapID: String, userInfo: [String: Any]) {
        // Load swap details from file
        if let ongoingSwap = self.bittrWallet.ongoingSwap ?? CacheManager.getLatestSwap() {
            print("Loaded swap details from background.")
            
            // Clear the notification handling flag and hide pending view
            self.needsToHandleNotification = false
            self.pendingSpinner.stopAnimating()
            self.pendingView.alpha = 0
            self.blackSignupBackground.alpha = 0
            
            // Reset the double handling flag
            self.isHandlingSwapNotification = false
            
            // Go directly to swap screen without showing alert
            DispatchQueue.main.async {
                self.openSwapViewController()
            }
        } else {
            // Could not load swap details, clear the notification handling flag
            self.needsToHandleNotification = false
            self.pendingSpinner.stopAnimating()
            self.pendingView.alpha = 0
            self.blackSignupBackground.alpha = 0
            
            // Reset the double handling flag
            self.isHandlingSwapNotification = false
        }
    }
    
    @objc func openSwapViewController() {
        // Use the existing pending swap functionality
        // The swap details are already stored in ongoingSwapDictionary
        // We just need to present the SwapViewController and it will handle the pending swap
        
        // Try to present through HomeViewController using the existing segue
        if let homeVC = self.homeVC {
            homeVC.performSegue(withIdentifier: "HomeToMove", sender: homeVC)
            
            // After a short delay, trigger the swap button tap to go directly to swap
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if let moveVC = homeVC.presentedViewController as? MoveViewController {
                    // Set a flag to indicate this is from a background notification
                    moveVC.isFromBackgroundNotification = true
                    moveVC.performSegue(withIdentifier: "MoveToSwap", sender: moveVC)
                }
            }
        }
    }
    
    private func isSwapViewControllerOpen() -> Bool {
        // Check if SwapViewController is currently presented in the view hierarchy
        if let homeVC = self.homeVC {
            // Check if HomeViewController has a presented view controller
            if let presentedVC = homeVC.presentedViewController {
                // Check if it's MoveViewController
                if let moveVC = presentedVC as? MoveViewController {
                    // Check if MoveViewController has a presented view controller (SwapViewController)
                    if let swapVC = moveVC.presentedViewController as? SwapViewController {
                        return true
                    }
                }
                // Check if it's directly SwapViewController
                if presentedVC is SwapViewController {
                    return true
                }
            }
        }
        return false
    }

}
