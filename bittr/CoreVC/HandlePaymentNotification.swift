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
                
                if self.userDidSignIn {
                    // User has signed in.
                    
                    if !self.wasNotified {
                        // App was open when notification came in.
                        self.varSpecialData = specialData
                        self.showAlert(presentingController: self, title: Language.getWord(withID: "bittrpayout"), message: Language.getWord(withID: "newbittrpayment"), buttons: [Language.getWord(withID: "okay")], actions: [#selector(self.triggerPayout)])
                    } else {
                        // App was closed when notification came in and was subsequently opened.
                        self.pendingLabel.text = Language.getWord(withID: "receivingpayment")
                        self.showPendingView()
                        
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
            } else if userInfo["payment_request_id"] is String {
                // LNURL
                self.handleLightningAddressNotification(notification: notification)
            } else {
                // No special key, so this is a normal notification.
                print("No special key found in notification.")
                self.hidePendingView()
                self.showAlert(presentingController: self, title: Language.getWord(withID: "notification"), message: Language.getWord(withID: "notificationhandlingfail"), buttons: [Language.getWord(withID: "okay")], actions: nil)
            }
        } else {
            // Hide loading UI
            self.hidePendingView()
            self.showAlert(presentingController: self, title: Language.getWord(withID: "notification"), message: Language.getWord(withID: "notificationhandlingfail"), buttons: [Language.getWord(withID: "okay")], actions: nil)
        }
    }
    
    func hidePendingView() {
        self.pendingSpinner.stopAnimating()
        self.pendingView.alpha = 0
        self.blackSignupBackground.alpha = 0
    }
    
    func showPendingView() {
        self.pendingSpinner.startAnimating()
        self.pendingView.alpha = 1
        self.blackSignupBackground.alpha = 0.2
    }
    
    @objc func triggerPayout() {
        self.hideAlert()
        self.pendingLabel.text = Language.getWord(withID: "receivingpayment")
        self.showPendingView()
        self.facilitateNotificationPayout()
        self.needsToHandleNotification = false
    }
    
    
    @objc func facilitateNotificationPayout() {
        self.hideAlert()
        
        let nodeId = EnvironmentConfig.lightningNodeId
        
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
                        self.hidePendingView()
                        self.showAlert(presentingController: self, title: Language.getWord(withID: "bittrpayout"), message: Language.getWord(withID: "couldntconnect"), buttons: [Language.getWord(withID: "close"), Language.getWord(withID: "tryagain")], actions: [nil, #selector(self.reconnectToPeer)])
                    }
                } else if peers[0].nodeId == nodeId, peers[0].isConnected == false {
                    DispatchQueue.main.async {
                        self.hidePendingView()
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
                        
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                            
                            self.hidePendingView()
                            
                            if let invoiceHash = self.getInvoiceHash(invoiceString: invoice.description), let paymentDetails = LightningNodeService.shared.getPaymentDetails(paymentHash: invoiceHash) {
                                
                                let receivedTransaction = self.createTransaction(transactionDetails: nil, paymentDetails: paymentDetails, bittrTransaction: nil, coreVC: self, bittrTransactions: nil)
                                receivedTransaction.isBittr = true
                                receivedTransaction.lnDescription = notificationId
                                
                                self.receivedBittrTransaction = receivedTransaction
                                
                                self.homeVC?.addLightningTransaction(thisTransaction: receivedTransaction, paymentDetails: paymentDetails)
                                self.performSegue(withIdentifier: "CoreToLightning", sender: self)
                            }
                        }
                    } catch {
                        print("Error occurred: \(error.localizedDescription)")
                        DispatchQueue.main.async {
                            SentrySDK.capture(error: error)
                            self.hidePendingView()
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
            self.hidePendingView()
            self.showAlert(presentingController: self, title: Language.getWord(withID: "bittrpayout"), message: Language.getWord(withID: "bittrpayoutfail"), buttons: [Language.getWord(withID: "close")], actions: nil)
        }
    }
    
    
    @objc func reconnectToPeer() {
        self.hideAlert()
        
        // Connect to Lightning peer.
        let nodeId = EnvironmentConfig.lightningNodeId
        let address = EnvironmentConfig.lightningNodeAddress
        
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
        
        if CacheManager.hasHandledEvent(event: "\(event)") {
            // Event has already been handled.
            print("Event was handled before.")
        } else {
            // New event.
            switch event {
            case .paymentReceived(paymentId: _, paymentHash: let paymentHash, amountMsat: _, customRecords: _):
                
                if self.varSpecialData != nil {
                    // This is a Bittr payment, which is being handled separately.
                    CacheManager.didHandleEvent(event: "\(event)")
                } else if let paymentDetails = LightningNodeService.shared.getPaymentDetails(paymentHash: paymentHash) {
                    
                    print("Did receive payment details.")
                    
                    let thisTransaction = self.createTransaction(transactionDetails: nil, paymentDetails: paymentDetails, bittrTransaction: nil, coreVC: self, bittrTransactions: nil)
                    
                    self.receivedBittrTransaction = thisTransaction
                    
                    DispatchQueue.main.async {
                        CacheManager.didHandleEvent(event: "\(event)")
                        self.homeVC?.addLightningTransaction(thisTransaction: thisTransaction, paymentDetails: paymentDetails)
                        if !CacheManager.getInvoiceDescription(hash: paymentHash).contains("Swap onchain to lightning ") {
                            self.performSegue(withIdentifier: "CoreToLightning", sender: self)
                        }
                    }
                }
            case .channelClosed(channelId: _, userChannelId: _, counterpartyNodeId: _, reason: _):
                
                DispatchQueue.main.async {
                    CacheManager.didHandleEvent(event: "\(event)")
                    self.launchQuestion(question: Language.getWord(withID: "closedlightningchannel"), answer: Language.getWord(withID: "closedlightningchannel2"), type: nil)
                }
            case .channelPending(channelId: _, userChannelId: _, formerTemporaryChannelId: _, counterpartyNodeId: _, fundingTxo: let fundingTxo):
                
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
                                            
                                            let thisTransaction = self.createTransaction(transactionDetails: nil, paymentDetails: nil, bittrTransaction: eachTransaction, coreVC: self.homeVC?.coreVC, bittrTransactions: self.homeVC?.bittrTransactions)
                                            
                                            self.receivedBittrTransaction = thisTransaction
                                            self.homeVC?.addLightningTransaction(thisTransaction: thisTransaction, paymentDetails: nil)
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
            case .paymentSuccessful(paymentId: _, paymentHash: _, paymentPreimage: _, feePaidMsat: _):
                return
            case .paymentFailed(paymentId: _, paymentHash: _, reason: _):
                return
            case .paymentClaimable(paymentId: _, paymentHash: _, claimableAmountMsat: _, claimDeadline: _, customRecords: _):
                return
            case .paymentForwarded(prevChannelId: _, nextChannelId: _, prevUserChannelId: _, nextUserChannelId: _, prevNodeId: _, nextNodeId: _, totalFeeEarnedMsat: _, skimmedFeeMsat: _, claimFromOnchainTx: _, outboundAmountForwardedMsat: _):
                return
            case .channelReady(channelId: _, userChannelId: _, counterpartyNodeId: _):
                return
            }
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
            if self.userDidSignIn {
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
        if (self.bittrWallet.ongoingSwap ?? CacheManager.getLatestSwap()) != nil {
            print("Loaded swap details from background.")
            
            // Clear the notification handling flag and hide pending view
            self.needsToHandleNotification = false
            self.hidePendingView()
            
            // Reset the double handling flag
            self.isHandlingSwapNotification = false
            
            // Go directly to swap screen without showing alert
            DispatchQueue.main.async {
                self.openSwapViewController()
            }
        } else {
            // Could not load swap details, clear the notification handling flag
            self.needsToHandleNotification = false
            self.hidePendingView()
            
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
