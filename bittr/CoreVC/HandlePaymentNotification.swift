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
        
        print("=== handlePaymentNotification called ===")
        print("userDidSignIn: \(self.userDidSignIn)")
        print("wasNotified: \(self.wasNotified)")
        print("needsToHandleNotification: \(self.needsToHandleNotification)")
        
        if let userInfo = notification.userInfo as [AnyHashable:Any]? {
            
            // Check for the special key that indicates this is a silent notification.
            if let specialData = userInfo["bittr_specific_data"] as? [String: Any] {
                print("Received special data: \(specialData)")
                
                CacheManager.storeLatestNotification(specialData: specialData)
                
                // Check if we received a notification while the app was closed
                let receivedNotificationWhileClosed = UserDefaults.standard.bool(forKey: "receivedNotificationWhileClosed")
                print("receivedNotificationWhileClosed: \(receivedNotificationWhileClosed), wasNotified: \(self.wasNotified)")
                
                if self.userDidSignIn {
                    // User has signed in.
                    print("User is signed in, processing notification")
                    
                    if !receivedNotificationWhileClosed && !self.wasNotified {
                        // App was open when notification came in.
                        print("App was open when notification came in - showing alert")
                        self.varSpecialData = specialData
                        self.showAlert(presentingController: self, title: Language.getWord(withID: "bittrpayout"), message: Language.getWord(withID: "newbittrpayment"), buttons: [Language.getWord(withID: "okay")], actions: [#selector(self.triggerPayout)])
                    } else {
                        // App was closed when notification came in and was subsequently opened.
                        print("App was closed when notification came in - processing immediately")
                        self.pendingLabel.text = Language.getWord(withID: "receivingpayment")
                        self.showPendingView()
                        
                        self.varSpecialData = specialData
                        self.facilitateNotificationPayout()
                        self.needsToHandleNotification = false
                    }
                    
                    // Clear the flag after handling, regardless of which path we took
                    UserDefaults.standard.set(false, forKey: "receivedNotificationWhileClosed")
                    print("Cleared receivedNotificationWhileClosed flag")
                } else {
                    // User hasn't signed in yet.
                    print("User not signed in - storing notification for later")
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
            print("Bitcoin amount: \(bitcoinAmountString)")
            let bitcoinAmount = Decimal(string: bitcoinAmountString) ?? Decimal(0)
            let amountMsat = UInt64(truncating: (bitcoinAmount * Decimal(100_000_000_000)) as NSDecimalNumber)
            print("Amount msat: \(amountMsat)")
            
            let pubkey = LightningNodeService.shared.nodeId()
            print("Did get public key.")

            // Call payoutLightning in an async context
            Task.init {
                
                let peers = try await LightningNodeService.shared.listPeers()
                print("Did list peers.")
                var peerIsConnected = false
                for eachPeer in peers {
                    if eachPeer.nodeId == EnvironmentConfig.lightningNodeId, eachPeer.isConnected {
                        peerIsConnected = true
                    }
                }
                if peers.count == 0 || !peerIsConnected {
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
                        
                        // Cache payment details.
                        if let invoiceHash = self.getInvoiceHash(invoiceString: invoice.description), let paymentDetails = LightningNodeService.shared.getPaymentDetails(paymentHash: invoiceHash) {
                            let newTimestamp = Int(Date().timeIntervalSince1970)
                            CacheManager.storeInvoiceTimestamp(preimage: paymentDetails.kind.preimageAsString ?? paymentDetails.id, timestamp: newTimestamp)
                            CacheManager.storeInvoiceDescription(preimage: paymentDetails.kind.preimageAsString ?? paymentDetails.id, desc: notificationId)
                            print("Did cache invoice data.")
                        }
                        
                        let lightningSignature = try await LightningNodeService.shared.signMessage(message: notificationId)
                        print("Did sign message.")
                        
                        let payoutResponse = try await BittrService.shared.payoutLightning(notificationId: notificationId, invoice: invoice.description, signature: lightningSignature, pubkey: pubkey)
                        print("Payout successful. PreImage: \(payoutResponse.preImage ?? "N/A")")
                        
                        DispatchQueue.main.async {
                            self.hidePendingView()
                        }
                    } catch let error as BittrServiceError {
                        print("BittrService error occurred: \(error.localizedDescription)")
                        DispatchQueue.main.async {
                            SentrySDK.capture(error: error) { scope in
                                scope.setExtra(value: "HandlePaymentNotification row 152", key: "context")
                            }
                            self.hidePendingView()
                            
                            switch error {
                            case .channelFullWithSwapSuggestion(let message, let suggestedAmount):
                                // Handle channel full with swap suggestion
                                self.handleChannelFullWithSwapSuggestion(message: message, suggestedAmount: suggestedAmount, notificationId: notificationId)
                            case .serverError(let message):
                                if message.contains("try again"), self.varSpecialData != nil {
                                    self.showAlert(presentingController: self, title: Language.getWord(withID: "bittrpayout"), message: message, buttons: [Language.getWord(withID: "close"), Language.getWord(withID: "tryagain")], actions: [nil, #selector(self.facilitateNotificationPayout)])
                                } else {
                                    self.showAlert(presentingController: self, title: Language.getWord(withID: "bittrpayout"), message: message, buttons: [Language.getWord(withID: "close")], actions: nil)
                                }
                            default:
                                self.showAlert(presentingController: self, title: Language.getWord(withID: "bittrpayout"), message: error.localizedDescription, buttons: [Language.getWord(withID: "close")], actions: nil)
                            }
                        }
                    } catch {
                        print("General error occurred: \(error.localizedDescription)")
                        DispatchQueue.main.async {
                            SentrySDK.capture(error: error) { scope in
                                scope.setExtra(value: "HandlePaymentNotification row 174", key: "context")
                            }
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
        
        Task {
            await LightningNodeService.shared.didEstablishPeerConnection()
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
            CacheManager.didHandleEvent(event: "\(event)")
            
            switch event {
            case .paymentReceived(paymentId: _, paymentHash: let paymentHash, amountMsat: _, customRecords: _):
                
                if let paymentDetails = LightningNodeService.shared.getPaymentDetails(paymentHash: paymentHash) {
                    print("Did receive payment details.")
                    
                    if self.varSpecialData != nil {
                        // This is an incoming Bittr payout.
                        self.checkPaymentWithBittr(paymentPreimage: paymentDetails.kind.preimageAsString ?? paymentDetails.id, paymentDetails: paymentDetails, isFundingTransaction: false)
                    } else {
                        // This is a normal incoming payment.
                        let thisTransaction = paymentDetails.createTransaction(coreVC: self, bittrTransactions: nil)
                        self.launchPaymentVC(thisTransaction: thisTransaction, paymentDetails: paymentDetails)
                    }
                }
            case .channelClosed(channelId: _, userChannelId: _, counterpartyNodeId: _, reason: let reason):
                DispatchQueue.main.async {
                    var answer = Language.getWord(withID: "closedlightningchannel2")
                    if reason != nil {
                        switch reason! {
                        case .counterpartyForceClosed(peerMsg: _):
                            answer = answer.replacingOccurrences(of: "<reason>", with: Language.getWord(withID: "closedlightningchannel3") + Language.getWord(withID: "counterpartyForceClosed"))
                        case .holderForceClosed(broadcastedLatestTxn: _):
                            answer = answer.replacingOccurrences(of: "<reason>", with: Language.getWord(withID: "closedlightningchannel3") + Language.getWord(withID: "holderForceClosed"))
                        case .legacyCooperativeClosure:
                            answer = answer.replacingOccurrences(of: "<reason>", with: Language.getWord(withID: "closedlightningchannel3") + Language.getWord(withID: "legacyCooperativeClosure"))
                        case .counterpartyInitiatedCooperativeClosure:
                            answer = answer.replacingOccurrences(of: "<reason>", with: Language.getWord(withID: "closedlightningchannel3") + Language.getWord(withID: "counterpartyInitiatedCooperativeClosure"))
                        case .locallyInitiatedCooperativeClosure:
                            answer = answer.replacingOccurrences(of: "<reason>", with: Language.getWord(withID: "closedlightningchannel3") + Language.getWord(withID: "locallyInitiatedCooperativeClosure"))
                        case .commitmentTxConfirmed:
                            answer = answer.replacingOccurrences(of: "<reason>", with: Language.getWord(withID: "closedlightningchannel3") + Language.getWord(withID: "commitmentTxConfirmed"))
                        case .fundingTimedOut:
                            answer = answer.replacingOccurrences(of: "<reason>", with: Language.getWord(withID: "closedlightningchannel3") + Language.getWord(withID: "fundingTimedOut"))
                        case .processingError(err: let err):
                            answer = answer.replacingOccurrences(of: "<reason>", with: Language.getWord(withID: "closedlightningchannel3") + err.lowercased())
                        case .disconnectedPeer:
                            answer = answer.replacingOccurrences(of: "<reason>", with: Language.getWord(withID: "closedlightningchannel3") + Language.getWord(withID: "disconnectedPeer"))
                        case .outdatedChannelManager:
                            answer = answer.replacingOccurrences(of: "<reason>", with: Language.getWord(withID: "closedlightningchannel3") + Language.getWord(withID: "outdatedChannelManager"))
                        case .counterpartyCoopClosedUnfundedChannel:
                            answer = answer.replacingOccurrences(of: "<reason>", with: Language.getWord(withID: "closedlightningchannel3") + Language.getWord(withID: "counterpartyCoopClosedUnfundedChannel"))
                        case .fundingBatchClosure:
                            answer = answer.replacingOccurrences(of: "<reason>", with: Language.getWord(withID: "closedlightningchannel3") + Language.getWord(withID: "fundingBatchClosure"))
                        case .htlCsTimedOut:
                            answer = answer.replacingOccurrences(of: "<reason>", with: Language.getWord(withID: "closedlightningchannel3") + Language.getWord(withID: "htlCsTimedOut"))
                        case .peerFeerateTooLow(peerFeerateSatPerKw: _, requiredFeerateSatPerKw: _):
                            answer = answer.replacingOccurrences(of: "<reason>", with: Language.getWord(withID: "closedlightningchannel3") + Language.getWord(withID: "peerFeerateTooLow"))
                        }
                    }
                    answer = answer.replacingOccurrences(of: "<reason>", with: "")
                    self.launchQuestion(question: Language.getWord(withID: "closedlightningchannel"), answer: answer, type: nil)
                    self.syncLDKnode()
                }
            case .channelPending(channelId: _, userChannelId: _, formerTemporaryChannelId: _, counterpartyNodeId: _, fundingTxo: let fundingTxo):
                
                // New Bittr channel. Get funding transaction details.
                self.checkPaymentWithBittr(paymentPreimage: fundingTxo.txid, paymentDetails: nil, isFundingTransaction: true)
                
            case .paymentSuccessful(paymentId: _, paymentHash: let paymentHash, paymentPreimage: _, feePaidMsat: let feePaidMsat):
                
                if let paymentDetails = LightningNodeService.shared.getPaymentDetails(paymentHash: paymentHash) {
                    
                    // Create transaction item.
                    let newTransaction = paymentDetails.createTransaction(coreVC: self, bittrTransactions: nil)
                    if feePaidMsat != nil, Int(feePaidMsat!/1000) > 0 {
                        CacheManager.storePaymentFees(preimage: newTransaction.id, fees: Int(feePaidMsat!/1000))
                        newTransaction.fee = Int(feePaidMsat!/1000)
                    }
                    
                    // Check if SendVC or ReceiveVC is open.
                    DispatchQueue.main.async {
                        let sendVC = (self.homeVC!.presentedViewController as? SendViewController ?? self.homeVC!.moveVC?.presentedViewController as? SendViewController)
                        let receiveVC = (self.homeVC!.presentedViewController as? ReceiveViewController ?? self.homeVC!.moveVC?.presentedViewController as? ReceiveViewController)
                        if sendVC ?? receiveVC != nil {
                            // SendVC or ReceiveVC if open. Handle transaction there.
                            (sendVC ?? receiveVC)!.addNewPaymentToTable(thisPayment: paymentDetails, delegate: (sendVC ?? receiveVC)!)
                        } else {
                            // Handle transaction in HomeVC.
                            self.homeVC!.addLightningTransaction(thisTransaction: newTransaction, paymentDetails: paymentDetails)
                            if !newTransaction.isSwap, !newTransaction.lnDescription.contains("Swap onchain to lightning "), !newTransaction.lnDescription.contains("Swap lightning to onchain ") {
                                self.homeVC!.tappedTransaction = newTransaction
                                self.homeVC!.performSegue(withIdentifier: "HomeToTransaction", sender: self)
                            }
                            CacheManager.storeLightningTransaction(thisTransaction: newTransaction)
                        }
                    }
                }
            case .paymentFailed(paymentId: _, paymentHash: _, reason: let reason):
                
                // Check if SendVC or ReceiveVC is active.
                DispatchQueue.main.async {
                    let sendVC = (self.homeVC!.presentedViewController as? SendViewController ?? self.homeVC!.moveVC?.presentedViewController as? SendViewController)
                    let receiveVC = (self.homeVC!.presentedViewController as? ReceiveViewController ?? self.homeVC!.moveVC?.presentedViewController as? ReceiveViewController)
                    
                    // Update views.
                    sendVC?.nextLabel.alpha = 1
                    sendVC?.nextSpinner.stopAnimating()
                    sendVC?.resetFields()
                    
                    // Parse failure reason.
                    var failureReason = ""
                    switch reason {
                    case .none: break
                    case .some(let receivedReason):
                        switch receivedReason {
                        case .recipientRejected: failureReason = Language.getWord(withID: "recipientRejected")
                        case .userAbandoned: failureReason = Language.getWord(withID: "userAbandoned")
                        case .retriesExhausted: failureReason = Language.getWord(withID: "retriesExhausted")
                        case .paymentExpired: failureReason = Language.getWord(withID: "paymentExpired")
                        case .routeNotFound: failureReason = Language.getWord(withID: "routeNotFound")
                        case .unexpectedError: failureReason = Language.getWord(withID: "unexpectederror")
                        case .unknownRequiredFeatures: failureReason = Language.getWord(withID: "unknownRequiredFeatures")
                        case .invoiceRequestExpired: failureReason = Language.getWord(withID: "invoiceRequestExpired")
                        case .invoiceRequestRejected: failureReason = Language.getWord(withID: "invoiceRequestRejected")
                        case .blindedPathCreationFailed: failureReason = Language.getWord(withID: "blindedPathCreationFailed")
                        }
                    }
                    
                    // Show alert.
                    self.showAlert(presentingController: (sendVC ?? receiveVC ?? self), title: Language.getWord(withID: "paymentfailed"), message: Language.getWord(withID: "paymentfailed2").replacingOccurrences(of: "<reason>", with: failureReason), buttons: [Language.getWord(withID: "okay")], actions: nil)
                }
                
            case .paymentClaimable(paymentId: _, paymentHash: _, claimableAmountMsat: _, claimDeadline: _, customRecords: _):
                return
            case .paymentForwarded(prevChannelId: _, nextChannelId: _, prevUserChannelId: _, nextUserChannelId: _, prevNodeId: _, nextNodeId: _, totalFeeEarnedMsat: _, skimmedFeeMsat: _, claimFromOnchainTx: _, outboundAmountForwardedMsat: _):
                return
            case .channelReady(channelId: _, userChannelId: _, counterpartyNodeId: _):
                self.syncLDKnode()
            }
        }
    }
    
    func launchPaymentVC(thisTransaction:Transaction, paymentDetails:PaymentDetails?) {
        
        self.receivedBittrTransaction = thisTransaction
        
        DispatchQueue.main.async {
            self.homeVC?.addLightningTransaction(thisTransaction: thisTransaction, paymentDetails: paymentDetails)
            if !CacheManager.getInvoiceDescription(preimage: thisTransaction.id).contains("Swap onchain to lightning ") {
                self.performSegue(withIdentifier: "CoreToLightning", sender: self)
            }
            CacheManager.storeLightningTransaction(thisTransaction: thisTransaction)
        }
    }
    
    func checkPaymentWithBittr(paymentPreimage:String, paymentDetails:PaymentDetails?, isFundingTransaction:Bool) {
        
        // Get deposit codes.
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
                    let bittrApiTransactions = try await BittrService.shared.fetchBittrTransactions(txIds: [paymentPreimage], depositCodes: depositCodes)
                    print("Bittr transactions: \(bittrApiTransactions.count)")
                    
                    // Debug: Print the raw API response data
                    if bittrApiTransactions.count > 0, let firstTransaction = bittrApiTransactions.first {
                        print("DEBUG - Bittr API returned transaction:")
                        print("  - txId: \(firstTransaction.txId)")
                        print("  - bitcoinAmount: '\(firstTransaction.bitcoinAmount)'")
                        print("  - purchaseAmount: '\(firstTransaction.purchaseAmount)'")
                        print("  - currency: '\(firstTransaction.currency)'")
                        print("  - transferFee: '\(firstTransaction.transferFee)'")
                        print("  - datetime: '\(firstTransaction.datetime)'")
                    }
                    
                    CacheManager.updateSentToBittr(txids: [paymentPreimage])
                    
                    if bittrApiTransactions.count == 1, bittrApiTransactions.first != nil, bittrApiTransactions.first!.txId == paymentPreimage {
                        DispatchQueue.main.async {
                            
                            // Add payout ID to cache.
                            if self.varSpecialData != nil, let notificationId = self.varSpecialData!["notification_id"] as? String {
                                CacheManager.storeInvoiceDescription(preimage: paymentPreimage, desc: notificationId)
                            }
                            
                            // Create transaction object.
                            let thisTransaction = bittrApiTransactions.first!.createTransaction(coreVC: self, isFundingTransaction: isFundingTransaction)
                            self.launchPaymentVC(thisTransaction: thisTransaction, paymentDetails: nil)
                        }
                    } else {
                        print("channelPending: Received no transaction details from Bittr API. Funding txid: \(paymentPreimage)")
                        if paymentDetails != nil {
                            let thisTransaction = paymentDetails!.createTransaction(coreVC: self, bittrTransactions: nil)
                            self.launchPaymentVC(thisTransaction: thisTransaction, paymentDetails: paymentDetails!)
                        }
                    }
                } catch {
                    print("channelPending Bittr error: \(error.localizedDescription)")
                    DispatchQueue.main.async {
                        SentrySDK.capture(error: error) { scope in
                            scope.setExtra(value: "HandlePaymentNotification row 453", key: "context")
                        }
                        if paymentDetails != nil {
                            let thisTransaction = paymentDetails!.createTransaction(coreVC: self, bittrTransactions: nil)
                            self.launchPaymentVC(thisTransaction: thisTransaction, paymentDetails: paymentDetails!)
                        }
                    }
                }
            }
        }
    }
    
    func syncLDKnode() {
        if let nodeStatus = LightningNodeService.shared.status(), nodeStatus.isRunning {
            do {
                // Sync LDK node.
                try LightningNodeService.shared.syncWallets()
                print("Did sync LDK node.")
                
                Task {
                    // Fetch channel details.
                    self.bittrWallet.lightningChannels = try await LightningNodeService.shared.listChannels()
                    print("Did list channels.")
                    
                    // Reset balance and transactions.
                    DispatchQueue.main.async {
                        print("Will reload wallet data.")
                        self.homeVC!.loadWalletData()
                    }
                }
            } catch {
                print("Could not sync LDK node or fetch channels. \(error.localizedDescription)")
                DispatchQueue.main.async {
                    SentrySDK.capture(error: error) { scope in
                        scope.setExtra(value: "HandlePaymentNotification row 484", key: "context")
                    }
                }
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
                
                // Clear the flag after handling
                UserDefaults.standard.set(false, forKey: "receivedNotificationWhileClosed")
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
        
        self.needsToHandleNotification = false
        self.isHandlingSwapNotification = false
        self.hidePendingView()
        
        // Load swap details from file
        if (self.bittrWallet.ongoingSwap ?? CacheManager.getLatestSwap()) != nil {
            print("Loaded swap details from background.")
            
            // Go directly to swap screen without showing alert
            DispatchQueue.main.async {
                self.openSwapViewController()
            }
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
    
    func handleChannelFullWithSwapSuggestion(message: String, suggestedAmount: String, notificationId: String) {
        // Store the notification data for later use after swap
        self.pendingNotificationData = self.varSpecialData
        self.pendingNotificationId = notificationId
        self.pendingSuggestedSwapAmount = Int(suggestedAmount) ?? 50000
        
        // Show alert with swap suggestion
        let recommendationMessage = Language.getWord(withID: "channelfullswaprecommendation").replacingOccurrences(of: "<amount>", with: suggestedAmount)
        self.showAlert(
            presentingController: self,
            title: Language.getWord(withID: "insufficientfunds"),
            message: "\(message)\n\n\(recommendationMessage)",
            buttons: [Language.getWord(withID: "receiveonchain"), Language.getWord(withID: "swapandreceiveinstantly")],
            actions: [#selector(self.receiveOnchainForNotification), #selector(self.swapAndPayForNotification)]
        )
    }
    
    @objc override func cancelSwapOffer() {
        self.hideAlert()
        // Clear pending data
        self.pendingNotificationData = nil
        self.pendingNotificationId = nil
        self.pendingSuggestedSwapAmount = 0
    }
    
    @objc func receiveOnchainForNotification() {
        self.hideAlert()
        
        guard let notificationId = self.pendingNotificationId else {
            print("ERROR: No pending notification ID for on-chain payout")
            return
        }
        
        // Show loading state
        self.pendingLabel.text = Language.getWord(withID: "receivingpayment")
        self.showPendingView()
        
        Task {
            do {
                let pubkey = LightningNodeService.shared.nodeId()
                let signature = try await LightningNodeService.shared.signMessage(message: notificationId)
                
                let response = try await BittrService.shared.markTransactionAsOnchain(
                    notificationId: notificationId,
                    signature: signature,
                    pubkey: pubkey
                )
                
                print("On-chain payout marked successfully: \(response)")
                
                DispatchQueue.main.async {
                    self.hidePendingView()
                    self.showAlert(
                        presentingController: self,
                        title: "Payment Scheduled",
                        message: "Your payment has been scheduled for on-chain delivery within 4-24 hours. You'll receive a notification when it's completed.",
                        buttons: [Language.getWord(withID: "okay")],
                        actions: nil
                    )
                    
                    // Clear pending data
                    self.pendingNotificationData = nil
                    self.pendingNotificationId = nil
                    self.pendingSuggestedSwapAmount = 0
                }
                
            } catch {
                print("ERROR: Failed to mark transaction as on-chain: \(error)")
                DispatchQueue.main.async {
                    SentrySDK.capture(error: error) { scope in
                        scope.setExtra(value: "HandlePaymentNotification row 637", key: "context")
                    }
                    self.hidePendingView()
                    self.showAlert(
                        presentingController: self,
                        title: "Error",
                        message: "Failed to schedule on-chain payment: \(error.localizedDescription)",
                        buttons: [Language.getWord(withID: "okay")],
                        actions: nil
                    )
                }
            }
        }
    }
    
    @objc func swapAndPayForNotification() {
        self.hideAlert()
        
        // Navigate to swap screen using existing pattern
        if let homeVC = self.homeVC {
            // Use the stored suggested swap amount
            let suggestedAmount = self.pendingSuggestedSwapAmount
            print("DEBUG - swapAndPayForNotification: suggestedAmount=\(suggestedAmount)")
            
            // First dismiss the current view controller
            self.dismiss(animated: true) {
                // Then navigate through the existing segue pattern
                homeVC.performSegue(withIdentifier: "HomeToMove", sender: homeVC)
                
                // After a short delay, trigger the swap button tap to go directly to swap
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    if let moveVC = homeVC.presentedViewController as? MoveViewController {
                        // Set flags to trigger onchain-to-lightning swap with pre-filled amount
                        // We'll use a new flag to distinguish this from regular onchain payments
                        moveVC.isFromBackgroundNotification = true
                        moveVC.pendingOnchainAmount = suggestedAmount
                        moveVC.pendingOnchainAddress = "" // No specific address needed
                        moveVC.performSegue(withIdentifier: "MoveToSwap", sender: moveVC)
                    }
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
