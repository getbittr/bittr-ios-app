//
//  HandlePaymentNotification.swift
//  bittr
//
//  Created by Tom Melters on 08/02/2024.
//

import UIKit
import LDKNode

extension CoreViewController {
    
    func handlePayoutNotification(_ notification:BittrNotification) {
        Log.info("Will handle payout notification.")
        
        self.lightningNotification = notification
        
        if !self.userHasSignedIn {
            Log.info("User hasn't signed in yet. Storing notification for later.")
            self.wasNotified = true
            // No alert: let them unlock as quickly as possible.
        } else if !self.walletHasSynced {
            Log.info("Wallet hasn't synced yet.")
            self.showLoading(message: Language.getWord(withID: "syncingwallet3"))
        } else {
            Log.info("Wallet has synced. Will process notification.")
            if !self.wasNotified {
                // App was open when notification came in.
                Log.info("Will notify user of alert.")
                self.showAlert(presentingController: self, title: Language.getWord(withID: "bittrpayout"), message: Language.getWord(withID: "newbittrpayment"), buttons: [Language.getWord(withID: "okay")], actions: [#selector(self.triggerPayout)])
            } else {
                // App was closed when notification came in and was subsequently opened.
                Log.info("User has been notified of alert.")
                self.triggerPayout()
            }
        }
    }
    
    func handleHTLCNotification(_ notification: BittrNotification) {
        Log.info("Will handle HTLC (incoming payment) notification.")
        self.lightningNotification = notification
        if !self.userHasSignedIn {
            self.wasNotified = true
            // No alert: let them unlock as quickly as possible.
        } else if !self.walletHasSynced {
            self.showLoading(message: Language.getWord(withID: "syncingwallet3"))
        } else {
            if !self.wasNotified {
                self.showAlert(presentingController: self, title: Language.getWord(withID: "incomingpayment"), message: Language.getWord(withID: "newbittrpayment"), buttons: [Language.getWord(withID: "okay")], actions: [#selector(self.triggerHTLCReady)])
            } else {
                self.triggerHTLCReady()
            }
        }
    }
    
    @objc func triggerHTLCReady() {
        self.hideAlert()
        self.showLoading(message: Language.getWord(withID: "receivingpayment"))
        self.lightningNotification = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.facilitateHTLCReady()
        }
    }
    
    func handleHTLCExpiredNotification(_ notification: BittrNotification) {
        // Payment already failed; don't show any "incoming payment" modal.
        self.lightningNotification = nil
        let title = notification.headerText ?? Language.getWord(withID: "htlc_expired_title")
        let body = notification.bodyText ?? Language.getWord(withID: "htlc_expired_body")
        self.launchQuestion(question: title, answer: body, type: nil)
    }
    
    private func facilitateHTLCReady() {
        guard let depositCode = BitcoinManager.shared.bittrWallet.ibanEntities.first(where: { !$0.yourUniqueCode.isEmpty })?.yourUniqueCode else {
            self.hideLoading()
            self.showAlert(presentingController: self, title: Language.getWord(withID: "incomingpayment"), message: Language.getWord(withID: "bittrpayoutfail"), buttons: [Language.getWord(withID: "close")], actions: nil)
            return
        }
        guard let pubkey = BitcoinManager.shared.nodeId() else {
            self.hideLoading()
            self.showAlert(presentingController: self, title: Language.getWord(withID: "incomingpayment"), message: Language.getWord(withID: "bittrpayoutfail2"), buttons: [Language.getWord(withID: "close")], actions: nil)
            return
        }
        let timestamp = Int(Date().timeIntervalSince1970)
        let message = "htlc_ready:\(depositCode):\(timestamp)"
        Task {
            do {
                let signature = try await BitcoinManager.shared.signMessage(message: message)
                let response = try await BittrService.shared.htlcReady(depositCode: depositCode, timestamp: timestamp, pubkey: pubkey, signature: signature)
                await MainActor.run {
                    self.hideLoading()
                    if response.success, response.action == "resumed" {
                        // No alert – the incoming payment screen will show automatically
                    } else if response.success, response.action == "failed_timeout" {
                        self.showAlert(presentingController: self, title: Language.getWord(withID: "incomingpayment"), message: Language.getWord(withID: "bittrpayoutfail"), buttons: [Language.getWord(withID: "close")], actions: nil)
                    } else {
                        // Backend returned 200 with success == false: translate
                        // the raw error code into a friendly message.
                        Log.info("htlc_ready failed: \(response.error ?? "unknown")")
                        self.showAlert(presentingController: self, title: Language.getWord(withID: "incomingpayment"), message: self.htlcReadyFriendlyMessage(forCode: response.error), buttons: [Language.getWord(withID: "close")], actions: nil)
                    }
                }
            } catch {
                await MainActor.run {
                    self.hideLoading()
                    // A non-2xx response makes htlcReady throw
                    // BittrServiceError.serverError(<raw code>), so pull the code
                    // out and map it too — otherwise the raw code (e.g.
                    // "no_held_htlc") would reach the user via localizedDescription.
                    Log.info("htlc_ready error: \(error.localizedDescription)")
                    var code: String? = nil
                    if let bittrError = error as? BittrServiceError, case let .serverError(message) = bittrError {
                        code = message
                    }
                    self.showAlert(presentingController: self, title: Language.getWord(withID: "incomingpayment"), message: self.htlcReadyFriendlyMessage(forCode: code), buttons: [Language.getWord(withID: "close")], actions: nil)
                }
            }
        }
    }

    // Maps a raw /htlc-interceptor/ready error code to a user-friendly message so
    // the backend's codes never reach the alert. "no_held_htlc" = Bittr is no
    // longer holding the inbound HTLC (the payment expired before the app came
    // online); anything else falls back to the generic processing-failed message.
    func htlcReadyFriendlyMessage(forCode code: String?) -> String {
        if code == "no_held_htlc" {
            return Language.getWord(withID: "htlcnoheld")
        }
        return Language.getWord(withID: "bittrpayoutfail2")
    }

    @objc func triggerPayout() {
        self.hideAlert()
        self.showLoading(message: Language.getWord(withID: "receivingpayment"))
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            self.facilitateNotificationPayout()
        }
    }
    
    @objc func facilitateNotificationPayout() {
        self.hideAlert()
        Log.info("Will start payout process.")
        
        // Extract required data.
        guard
            self.lightningNotification != nil,
            let notificationId = self.lightningNotification!.notificationID,
            let amountMsat = self.lightningNotification!.amountMsat
        else {
            Log.info("No notification available for handling.")
            SentryManager.capture("Required data unavailable while trying to handle notification payout.", context: "HandlePaymentNotification row 108")
            self.hideLoading()
            self.lightningNotification = nil
            self.showAlert(presentingController: self, title: Language.getWord(withID: "bittrpayout"), message: Language.getWord(withID: "bittrpayoutfail"), buttons: [Language.getWord(withID: "close")], actions: nil)
            return
        }
            
        // Get pubkey.
        guard let pubkey:String = BitcoinManager.shared.nodeId() else {
            Log.info("Pubkey unavailable.")
            self.showAlert(presentingController: self, title: Language.getWord(withID: "bittrpayout"), message: Language.getWord(withID: "bittrpayoutfail2"), buttons: [Language.getWord(withID: "close"), Language.getWord(withID: "tryagain")], actions: [nil, #selector(self.facilitateNotificationPayout)])
            return
        }

        // Call payoutLightning in an async context
        if isConnectedToPeer() {
            Log.info("Is connected to peer.")
            
            Task {
                // Create invoice.
                guard let invoice = await BitcoinManager.shared.getInvoice(
                    amountMsat: UInt64(amountMsat),
                    description: notificationId,
                    expirySecs: 3600)
                else {
                    DispatchQueue.main.async {
                        self.hideLoading()
                        self.lightningNotification = nil
                        self.showAlert(presentingController: self, title: Language.getWord(withID: "bittrpayout"), message: Language.getWord(withID: "bittrpayoutfail"), buttons: [Language.getWord(withID: "close")], actions: nil)
                    }
                    return
                }
                
                // Cache payment details.
                if let invoiceHash = invoice.description.getInvoiceHash(), let paymentDetails = BitcoinManager.shared.getPaymentDetails(paymentHash: invoiceHash) {
                    let newTimestamp = Int(Date().timeIntervalSince1970)
                    CacheManager.storeInvoiceTimestamp(preimage: paymentDetails.kind.transactionID ?? paymentDetails.id, timestamp: newTimestamp)
                    CacheManager.storeInvoiceDescription(preimage: paymentDetails.kind.transactionID ?? paymentDetails.id, desc: notificationId)
                    Log.info("Did cache invoice data.")
                }
                
                // Sign message.
                let lightningSignature:String
                do {
                    lightningSignature = try await BitcoinManager.shared.signMessage(message: notificationId)
                    Log.info("Did sign message.")
                } catch {
                    // Couldn't sign notification ID.
                    DispatchQueue.main.async {
                        SentryManager.capture(error, context: "HandlePaymentNotification row 163")
                        self.hideLoading()
                        self.lightningNotification = nil
                        self.showAlert(presentingController: self, title: Language.getWord(withID: "bittrpayout"), message: Language.getWord(withID: "bittrpayoutfail"), buttons: [Language.getWord(withID: "close")], actions: nil)
                    }
                    return
                }
                
                // Send response to Bittr.
                do {
                    let payoutResponse = try await BittrService.shared.payoutLightning(notificationId: notificationId, invoice: invoice.description, signature: lightningSignature, pubkey: pubkey)
                    
                    Log.info("Payout successful.")
                    print("PreImage: \(payoutResponse.preImage ?? "N/A")")
                    DispatchQueue.main.async {
                        CacheManager.didHandleNotification(notificationId)
                        self.hideLoading()
                    }
                } catch {
                    Log.info("Error occurred: \(error.localizedDescription)")
                    DispatchQueue.main.async {
                        self.hideLoading()
                        var sendToSentry = true
                        
                        if let bittrServiceError = error as? BittrServiceError {
                            switch bittrServiceError {
                            case .channelFullWithSwapSuggestion(let message, let suggestedAmount):
                                // Handle channel full with swap suggestion
                                self.handleChannelFullWithSwapSuggestion(message: message, suggestedAmount: suggestedAmount, notificationId: notificationId)
                            case .serverError(let message):
                                if message.contains("try again"), self.lightningNotification != nil {
                                    self.showAlert(presentingController: self, title: Language.getWord(withID: "bittrpayout"), message: message, buttons: [Language.getWord(withID: "close"), Language.getWord(withID: "tryagain")], actions: [nil, #selector(self.facilitateNotificationPayout)])
                                } else {
                                    self.showAlert(presentingController: self, title: Language.getWord(withID: "bittrpayout"), message: message, buttons: [Language.getWord(withID: "close")], actions: nil)
                                    if message == "This payment has already been processed." {
                                        // No need to notify Sentry.
                                        sendToSentry = false
                                    }
                                    self.lightningNotification = nil
                                }
                            default:
                                self.showAlert(presentingController: self, title: Language.getWord(withID: "bittrpayout"), message: error.localizedDescription, buttons: [Language.getWord(withID: "close")], actions: nil)
                                self.lightningNotification = nil
                            }
                        } else {
                            if error.localizedDescription.contains("try again"), self.lightningNotification != nil {
                                self.showAlert(presentingController: self, title: Language.getWord(withID: "bittrpayout"), message: "\(error.localizedDescription)", buttons: [Language.getWord(withID: "close"), Language.getWord(withID: "tryagain")], actions: [nil, #selector(self.facilitateNotificationPayout)])
                            } else {
                                self.showAlert(presentingController: self, title: Language.getWord(withID: "bittrpayout"), message: "\(error.localizedDescription)", buttons: [Language.getWord(withID: "close")], actions: nil)
                                self.lightningNotification = nil
                            }
                        }
                        
                        if sendToSentry {
                            SentryManager.capture(error, context: "HandlePaymentNotification row 152")
                        }
                    }
                }
            }
        } else {
            Log.info("Not connected to peer.")
            DispatchQueue.main.async {
                self.hideLoading()
                self.showAlert(presentingController: self, title: Language.getWord(withID: "bittrpayout"), message: Language.getWord(withID: "couldntconnect"), buttons: [Language.getWord(withID: "close"), Language.getWord(withID: "tryagain")], actions: [nil, #selector(self.reconnectToPeer)])
            }
        }
    }
    
    
    @objc func reconnectToPeer() {
        self.hideAlert()
        
        Task {
            _ = await BitcoinManager.shared.didEstablishPeerConnection()
            DispatchQueue.main.async {
                self.facilitateNotificationPayout()
            }
        }
    }
    
    func ldkEventReceived(event:LDKNode.Event) {
        
        print("Event found. \(event)")
        
        if CacheManager.hasHandledEvent(event: "\(event)"), !event.isPaymentFailed() {
            // Event has already been handled.
            Log.info("Event was handled before.")
        } else {
            // New event.
            CacheManager.didHandleEvent(event: "\(event)")
            
            switch event {
            case .paymentReceived(paymentId: _, paymentHash: let paymentHash, amountMsat: _, customRecords: _):
                
                if let paymentDetails = BitcoinManager.shared.getPaymentDetails(paymentHash: paymentHash) {
                    Log.info("Did receive payment details.")
                    
                    if self.lightningNotification != nil {
                        // This is an incoming Bittr payout.
                        self.checkPaymentWithBittr(paymentPreimage: paymentDetails.kind.transactionID ?? paymentDetails.id, paymentDetails: paymentDetails, isFundingTransaction: false)
                    } else {
                        // This is a normal incoming payment.
                        let thisTransaction = paymentDetails.createTransaction(bittrTransactions: nil)
                        self.launchTransactionVC(thisTransaction: thisTransaction, paymentDetails: paymentDetails)
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
                        case .locallyCoopClosedUnfundedChannel:
                            answer = answer.replacingOccurrences(of: "<reason>", with: Language.getWord(withID: "closedlightningchannel3") + Language.getWord(withID: "locallyCoopClosedUnfundedChannel"))
                        }
                    }
                    answer = answer.replacingOccurrences(of: "<reason>", with: "")
                    if !self.removingWalletForIncorrectPin {
                        self.launchQuestion(question: Language.getWord(withID: "closedlightningchannel"), answer: answer, type: nil)
                    }
                    self.syncLDKnode()
                }
            case .channelPending(channelId: _, userChannelId: _, formerTemporaryChannelId: _, counterpartyNodeId: _, fundingTxo: let fundingTxo):
                
                // New Bittr channel. Get funding transaction details.
                self.checkPaymentWithBittr(paymentPreimage: fundingTxo.txid, paymentDetails: nil, isFundingTransaction: true)
                
            case .paymentSuccessful(paymentId: _, paymentHash: let paymentHash, paymentPreimage: _, feePaidMsat: let feePaidMsat):
                
                if let paymentDetails = BitcoinManager.shared.getPaymentDetails(paymentHash: paymentHash) {
                    
                    // Create transaction item.
                    let newTransaction = paymentDetails.createTransaction(bittrTransactions: nil)
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
                            (sendVC ?? receiveVC)!.addNewPaymentToTable(thisPayment: paymentDetails)
                        } else {
                            // Handle transaction in HomeVC.
                            self.homeVC!.addLightningTransaction(thisTransaction: newTransaction, paymentDetails: paymentDetails)
                            if !newTransaction.isSwap, !newTransaction.isSwapPayment {
                                self.homeVC!.tappedTransaction = newTransaction
                                self.homeVC!.performSegue(withIdentifier: "HomeToTransaction", sender: self)
                            }
                            CacheManager.storeLightningTransaction(newTransaction)
                        }
                    }
                }
            case .paymentFailed(paymentId: _, paymentHash: _, reason: let reason):
                
                // Check if SendVC or ReceiveVC is active.
                DispatchQueue.main.async {
                    let sendVC = (self.homeVC!.presentedViewController as? SendViewController ?? self.homeVC!.moveVC?.presentedViewController as? SendViewController)
                    let receiveVC = (self.homeVC!.presentedViewController as? ReceiveViewController ?? self.homeVC!.moveVC?.presentedViewController as? ReceiveViewController)
                    let swapVC = self.swapVC
                    
                    // Update views. The confirm spinner has to be stopped here
                    // too, the way addNewPaymentToTable does on success: a
                    // payment LDK accepts and then fails asynchronously
                    // (routeNotFound, retriesExhausted, recipientRejected)
                    // leaves the user on the confirm screen, and the spinner
                    // now gates the Confirm button — so leaving it running
                    // would strand them with no way to retry.
                    sendVC?.nextLabel.alpha = 1
                    sendVC?.nextSpinner.stopAnimating()
                    sendVC?.confirmSendVC?.confirmLabel.alpha = 1
                    sendVC?.confirmSendVC?.confirmSpinner.stopAnimating()
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
                        
                        // Inform Sentry.
                        SentryManager.capture(failureReason, context: "HandlePaymentNotification row 341")
                    }
                    
                    // Show alert.
                    let reasonText = failureReason.isEmpty ? "" : " \(failureReason)."
                    self.showAlert(presentingController: (sendVC ?? receiveVC ?? swapVC ?? self), title: Language.getWord(withID: "paymentfailed"), message: Language.getWord(withID: "paymentfailed2").replacingOccurrences(of: "<reason>", with: reasonText), buttons: [Language.getWord(withID: "okay")], actions: nil)
                }
                
            case .paymentClaimable(paymentId: _, paymentHash: _, claimableAmountMsat: _, claimDeadline: _, customRecords: _):
                return
            case .paymentForwarded(prevChannelId: _, nextChannelId: _, prevUserChannelId: _, nextUserChannelId: _, prevNodeId: _, nextNodeId: _, totalFeeEarnedMsat: _, skimmedFeeMsat: _, claimFromOnchainTx: _, outboundAmountForwardedMsat: _):
                return
            case .channelReady(channelId: _, userChannelId: _, counterpartyNodeId: _, fundingTxo: _):
                self.syncLDKnode()
            case .splicePending(channelId: let channelId, userChannelId: let userChannelId, counterpartyNodeId: let counterpartyNodeId, newFundingTxo: let newFundingTxo):
                return
            case .spliceFailed(channelId: let channelId, userChannelId: let userChannelId, counterpartyNodeId: let counterpartyNodeId, abandonedFundingTxo: let abandonedFundingTxo):
                return
            }
        }
    }
    
    func launchTransactionVC(thisTransaction:Transaction, paymentDetails:PaymentDetails?) {
        
        if thisTransaction.isBittr {
            self.receivedBittrTransaction = thisTransaction
        } else {
            self.homeVC?.tappedTransaction = thisTransaction
        }
        
        DispatchQueue.main.async {
            // Add and cache transaction.
            self.homeVC?.addLightningTransaction(thisTransaction: thisTransaction, paymentDetails: paymentDetails)
            CacheManager.storeLightningTransaction(thisTransaction)
            
            // Launch TransactionVC after ReceiveVC has dismissed.
            let presentTransactionVC = { [weak self] in
                guard let self else { return }
                if !thisTransaction.isSwapPayment {
                    self.homeVC?.performSegue(withIdentifier: "HomeToTransaction", sender: self)
                }
            }
            if let receiveVC = self.receiveVC {
                receiveVC.dismiss(animated: true, completion: presentTransactionVC)
            } else {
                presentTransactionVC()
            }
        }
    }
    
    func checkPaymentWithBittr(paymentPreimage:String, paymentDetails:PaymentDetails?, isFundingTransaction:Bool) {
        
        // Don't doublecheck transaction against API.
        if CacheManager.getSentToBittr().contains(paymentPreimage) {
            Log.info("Transaction has already been checked with Bittr.")
            for eachTransaction in self.homeVC!.visibleTransactions {
                if eachTransaction.id == paymentPreimage {
                    Log.info("Found correct transaction in transactions table.")
                    self.receivedBittrTransaction = eachTransaction
                    DispatchQueue.main.async {
                        self.homeVC?.performSegue(withIdentifier: "HomeToTransaction", sender: self)
                    }
                }
            }
            return
        }
        
        // Get deposit codes.
        var depositCodes = [String]()
        for eachIbanEntity in BitcoinManager.shared.bittrWallet.ibanEntities {
            if eachIbanEntity.yourUniqueCode != "" {
                depositCodes += [eachIbanEntity.yourUniqueCode]
            }
        }
        
        DispatchQueue.global(qos: .background).asyncAfter(deadline: .now() + 3) {
            Log.info("Did wait to start API call.")
            
            Task {
                do {
                    let bittrApiTransactions = try await BittrService.shared.fetchBittrTransactions(txIds: [paymentPreimage], depositCodes: depositCodes)
                    Log.info("Bittr transactions: \(bittrApiTransactions.count)")
                    
                    // Debug: Print the raw API response data
                    if bittrApiTransactions.count > 0, let firstTransaction = bittrApiTransactions.first {
                        Log.info("DEBUG - Bittr API returned transaction:")
                        print("  - txId: \(firstTransaction.txId)")
                        print("  - bitcoinAmount: '\(firstTransaction.bitcoinAmount)'")
                        print("  - currency: '\(firstTransaction.currency)'")
                        print("  - transferFee: '\(firstTransaction.transferFee)'")
                        print("  - datetime: '\(firstTransaction.datetime)'")
                    }
                    
                    CacheManager.updateSentToBittr(txids: [paymentPreimage])
                    
                    if bittrApiTransactions.count == 1, bittrApiTransactions.first != nil, bittrApiTransactions.first!.txId == paymentPreimage {
                        DispatchQueue.main.async {
                            
                            // Add payout ID to cache.
                            if let notificationId = self.lightningNotification?.notificationID {
                                CacheManager.storeInvoiceDescription(preimage: paymentPreimage, desc: notificationId)
                                self.lightningNotification = nil
                            }
                            
                            // Create transaction object.
                            let thisTransaction = bittrApiTransactions.first!.createTransaction(isFundingTransaction: isFundingTransaction)
                            self.launchTransactionVC(thisTransaction: thisTransaction, paymentDetails: nil)
                        }
                    } else {
                        Log.info("channelPending: Received no transaction details from Bittr API.")
                        print("Funding txid: \(paymentPreimage)")
                        if paymentDetails != nil {
                            let thisTransaction = paymentDetails!.createTransaction(bittrTransactions: nil)
                            self.launchTransactionVC(thisTransaction: thisTransaction, paymentDetails: paymentDetails!)
                        }
                    }
                } catch {
                    Log.info("channelPending Bittr error: \(error.localizedDescription)")
                    DispatchQueue.main.async {
                        SentryManager.capture(error, context: "HandlePaymentNotification row 453")
                        if paymentDetails != nil {
                            let thisTransaction = paymentDetails!.createTransaction(bittrTransactions: nil)
                            self.launchTransactionVC(thisTransaction: thisTransaction, paymentDetails: paymentDetails!)
                        }
                    }
                }
            }
        }
    }
    
    func syncLDKnode() {
        if BitcoinManager.shared.status()?.isRunning == true {
            
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    // Sync LDK node.
                    try BitcoinManager.shared.syncWallets()
                    Log.info("Did sync LDK node.")
                    
                    // Fetch channel details.
                    let channels = BitcoinManager.shared.listChannels()
                    Log.info("Did list channels.")
                    
                    // Reset balance and transactions.
                    DispatchQueue.main.async {
                        BitcoinManager.shared.bittrWallet.lightningChannels = channels
                        Log.info("Will reload wallet data.")
                        self.homeVC!.loadWalletData()
                    }
                } catch {
                    Log.info("Could not sync LDK node. \(error.localizedDescription)")
                    SentryManager.capture(error, context: "HandlePaymentNotification row 484")
                }
            }
        }
    }
    
    func handleSwapNotificationFromBackground(_ notification: BittrNotification) {
        
        guard notification.swapID != nil else {
            Log.info("Swap ID is nil.")
            self.lightningNotification = nil
            return
        }
            
        Log.info("Received swap notification from background for ID.")
        
        // Check if SwapViewController is already open - if so, ignore the notification
        if self.swapVC != nil || self.homeVC?.swapStatusVC != nil {
            Log.info("SwapViewController is already open, ignoring notification")
            return
        }
        
        // Check if user is signed in (PIN has been entered)
        if !self.userHasSignedIn {
            Log.info("User hasn't signed in yet, store notification for later.")
            self.wasNotified = true
            self.lightningNotification = notification
            
            self.showAlert(presentingController: self, title: Language.getWord(withID: "swapstatusupdate"), message: Language.getWord(withID: "pleasesignin"), buttons: [Language.getWord(withID: "okay")], actions: nil)
        } else if !self.walletHasSynced {
            Log.info("Wallet hasn't synced yet.")
            self.lightningNotification = notification
            self.showLoading(message: Language.getWord(withID: "syncingwallet3"))
        } else {
            // User is signed in, handle notification immediately
            self.handleSwapNotificationImmediately()
        }
    }
    
    func handleSwapNotificationImmediately() {
        self.lightningNotification = nil
        self.hideLoading()
        
        // Load swap details from file
        if CacheManager.getLatestSwap() != nil {
            Log.info("Loaded swap details from background.")
            self.performSegue(withIdentifier: "HomeToSwapStatus", sender: self)
        }
    }
    
    func handleChannelFullWithSwapSuggestion(message: String, suggestedAmount: String, notificationId: String) {
        // Store the notification data for later use after swap
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
    
    @objc func receiveOnchainForNotification() {
        self.hideAlert()
        
        guard let notificationId = self.pendingNotificationId else {
            Log.info("ERROR: No pending notification ID for on-chain payout")
            return
        }
        
        // Show loading state
        self.showLoading(message: Language.getWord(withID: "receivingpayment"))
        
        // Get pubkey
        var pubkey = String()
        if let pubkeyString = BitcoinManager.shared.nodeId() {
            pubkey = pubkeyString
        } else {
            self.hideLoading()
            self.showAlert(
                presentingController: self,
                title: "Error",
                message: "Failed to schedule on-chain payment: Wallet has not been synced.",
                buttons: [Language.getWord(withID: "okay")],
                actions: nil
            )
            return
        }
        
        Task {
            do {
                let signature = try await BitcoinManager.shared.signMessage(message: notificationId)
                
                let response = try await BittrService.shared.markTransactionAsOnchain(
                    notificationId: notificationId,
                    signature: signature,
                    pubkey: pubkey
                )
                
                Log.info("On-chain payout marked successfully.")
                print("Payout response: \(response)")
                
                DispatchQueue.main.async {
                    self.hideLoading()
                    self.showAlert(
                        presentingController: self,
                        title: "Payment Scheduled",
                        message: "Your payment has been scheduled for on-chain delivery within 4-24 hours. You'll receive a notification when it's completed.",
                        buttons: [Language.getWord(withID: "okay")],
                        actions: nil
                    )
                    
                    // Clear pending data
                    self.pendingNotificationId = nil
                    self.pendingSuggestedSwapAmount = 0
                }
                
            } catch {
                Log.info("ERROR: Failed to mark transaction as on-chain: \(error)")
                DispatchQueue.main.async {
                    SentryManager.capture(error, context: "HandlePaymentNotification row 637")
                    self.hideLoading()
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
        // Use the stored suggested swap amount
        Log.info("swapAndPayForNotification called.")
        
        self.performSegue(withIdentifier: "CoreToSwap", sender: self)
    }

}
