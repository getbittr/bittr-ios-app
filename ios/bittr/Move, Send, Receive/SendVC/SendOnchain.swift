//
//  SendOnchain.swift
//  bittr
//
//  Created by Tom Melters on 02/07/2024.
//

import UIKit
import LDKNode
import BitcoinDevKit
import CodeScanner
import AVFoundation

extension SendViewController {
    
    func checkSendOnchain() {
        guard self.checkInternetConnection() else { return }
            
        // Check address.
        guard let enteredAddress = self.toTextField.text?.trimmingCharacters(in: .whitespacesAndNewlines), !enteredAddress.isEmpty else {
            self.showAlert(title: Language.getWord(withID: "oops"), message: Language.getWord(withID: "enterbitcoinaddress"), buttons: [.dismiss(Language.getWord(withID: "okay"))])
            return
        }
        
        // If the field holds a lightning destination — an LNURL/lightning address, a
        // bolt11 invoice, or a bolt12 offer — rather than an on-chain address, switch
        // to Instant and hand off to checkSendLightning. Mirrors how checkSendLightning
        // redirects an on-chain address back to Regular, so pasting/typing an invoice
        // on the wrong tab just works instead of failing to parse as an address.
        if enteredAddress.lowercased().contains("lnurl") || enteredAddress.lowercased().isValidEmail()
            || enteredAddress.bolt11Invoice() != nil || enteredAddress.bolt12Offer() != nil {
            self.onchainOrLightning = .lightning
            self.updateLabels()
            self.checkSendLightning()
            return
        }

        // A genuine onchain send is never an LNURL payment: drop any LNURL state
        // left over from a resolved-but-abandoned lightning-address payment. Without
        // this, a leftover note attaches to this onchain transaction (the shared
        // addNewPaymentToTable stores pendingLnurlNote keyed by whatever payment
        // completes next), and a leftover invoice could resurface on a later
        // lightning send.
        self.pendingLnurlInvoice = nil
        self.pendingLnurlNote = nil
        self.confirmLnurlEmail = nil

        // Check amount.
        guard let enteredAmount = self.amountTextField.text?.trimmingCharacters(in: .whitespacesAndNewlines), !enteredAmount.isEmpty else {
            self.showAlert(title: Language.getWord(withID: "oops"), message: Language.getWord(withID: "enteramount"), buttons: [.dismiss(Language.getWord(withID: "okay"))])
            return
        }
        
        // Convert the entered amount to satoshis.
        guard let enteredSatoshis = self.getSatoshisFrom(enteredAmount: enteredAmount) else { return }
        guard enteredSatoshis > 0 else {
            self.showAlert(title: Language.getWord(withID: "oops"), message: Language.getWord(withID: "enteramount"), buttons: [.dismiss(Language.getWord(withID: "okay"))])
            return
        }
        
        // Check balance.
        guard enteredSatoshis <= (BitcoinManager.shared.bittrWallet.satoshisOnchainSpendable ?? 0) else {
            Log.info("Insufficient onchain balance.")
            Log.info("Check if we have sufficient Lightning balance for a swap.")
            
            let availableLightningBalance = (BitcoinManager.shared.bittrWallet.lightningChannels.getActiveChannel()?.outboundCapacityMsat ?? 0)/1000
            
            if availableLightningBalance >= enteredSatoshis {
                Log.info("Offering Lightning swap option.")
                
                // Store the address for the swap
                self.pendingOnchainAddress = enteredAddress
                self.pendingOnchainAmount = enteredSatoshis
                self.showAlert(
                    title: Language.getWord(withID: "insufficientfunds"),
                    message: Language.getWord(withID: "onchaininsufficientfunds").replacingOccurrences(of: "<amount>", with: String(BitcoinManager.shared.bittrWallet.satoshisOnchain).addSpaces()) + "\n\n" + Language.getWord(withID: "swapinsufficientfundslightning").replacingOccurrences(of: "<amount>", with: "\(availableLightningBalance)".addSpaces()),
                    buttons: [.action(Language.getWord(withID: "cancel")) { self.cancelSwapOffer() }, .action(Language.getWord(withID: "swapandpay")) { self.swapAndPayOnchain() }])
                
            } else {
                Log.info("Lightning balance insufficient, showing regular insufficient funds message.")
                self.showAlert(title: Language.getWord(withID: "oops"), message: Language.getWord(withID: "spendablebalance"), buttons: [.dismiss(Language.getWord(withID: "okay"))])
            }
            return
        }
        Log.info("Sufficient onchain balance.")
        
        // Start button animation.
        self.nextLabel.alpha = 0
        self.arrowIcon.alpha = 0
        self.nextSpinner.startAnimating()
        
        // Set confirmation variables.
        self.confirmAddress = enteredAddress
        self.confirmSatoshis = enteredSatoshis
        
        // Create transaction.
        Task {
            guard let feeEstimates = await BitcoinManager.shared.getFeeEstimates() else {
                DispatchQueue.main.async {
                    self.nextLabel.alpha = 1
                    self.arrowIcon.alpha = 1
                    self.nextSpinner.stopAnimating()
                    self.showAlert(title: Language.getWord(withID: "oops"), message: "\(Language.getWord(withID: "cannotproceed")). Error: Couldn't fetch recommended fees.", buttons: [.dismiss(Language.getWord(withID: "okay"))])
                }
                return
            }
            self.feePerVbLow = feeEstimates.economy
            self.feePerVbMedium = feeEstimates.hour
            self.feePerVbHigh = feeEstimates.fastest
            
            // Check the maximum sendable onchain amount.
            let drain = try? BitcoinManager.shared.maximumSendableOnchainDrain(toAddress: enteredAddress, satPerVb: self.feePerVbMedium.wholeSatPerVb)
            
            // Check whether user tapped their available funds.
            if let quotedMaximum = self.maximumSendableOnchainSats, enteredSatoshis == quotedMaximum {
                // The entered amount matches the maximum sendable onchain funds.
                self.didTapAvailable = true
            }
            
            // Check whether the user intends to empty their onchain funds.
            if let drain = drain, self.didTapAvailable || enteredSatoshis >= Int(drain.sendableSats) {
                self.confirmSatoshis = Int(drain.sendableSats)
                self.drainTotalSats = Int(drain.sendableSats + drain.feeSats)
                self.isSendingMaximum = true
            } else {
                self.drainTotalSats = nil
                self.isSendingMaximum = false
            }
            
            // Get transaction size.
            let size:UInt64
            do {
                if self.isSendingMaximum, let drain = drain {
                    size = drain.vsize
                } else {
                    size = try BitcoinManager.shared.getSize(address: enteredAddress, amountSats: enteredSatoshis, selectedVbyte: self.feePerVbMedium)
                }
            } catch {
                Log.info("Error: \(error.localizedDescription)")

                // Recognized, user-actionable errors get a plain consumer message;
                // anything internal or unknown (incl. future BDK errors) falls back to
                // the generic "we couldn't proceed" line. Only capture genuine bugs to
                // Sentry — a bad/wrong-network address is user input, not a fault.
                var friendlyMessage: String?
                var sendToSentry = true
                if let bdkError = error as? BitcoinDevKit.CreateTxError {
                    friendlyMessage = bdkError.consumerFriendlyMessage()
                    if case .CoinSelection = bdkError { sendToSentry = false }
                } else if let bdkError = error as? BitcoinDevKit.AddressParseError {
                    friendlyMessage = bdkError.consumerFriendlyMessage()
                    sendToSentry = false
                }

                let message = friendlyMessage ?? (Language.getWord(withID: "cannotproceed") + ".")

                // Show alert.
                DispatchQueue.main.async {
                    self.nextLabel.alpha = 1
                    self.arrowIcon.alpha = 1
                    self.nextSpinner.stopAnimating()
                    self.showAlert(title: Language.getWord(withID: "oops"), message: message, buttons: [.dismiss(Language.getWord(withID: "okay"))])
                    if sendToSentry {
                        SentryManager.capture(error, context: "SendOnchain row 167")
                    }
                }
                return
            }
            self.confirmTxSize = Double(size)
            
            // Animation from main view to confirm view.
            DispatchQueue.main.async {
                self.nextLabel.alpha = 1
                self.arrowIcon.alpha = 1
                self.nextSpinner.stopAnimating()
                self.slideFromSendToConfirm()
            }
        }
    }
    
    func cancelSwapOffer() {
        // Clear the pending data when user cancels the swap offer
        self.pendingOnchainAddress = ""
        self.pendingOnchainAmount = 0
        // Also clear the amount field to make it obvious this is cancelled
        self.amountTextField.text = ""
    }
    
    func swapAndPayOnchain() {
        Log.info("swapAndPayOnchain called.")
        self.performSegue(withIdentifier: "SendToSwap", sender: self)
    }
}

extension ConfirmSendViewController {
    
    func proceedWithOnchainConfirmation() {
        
        let feeSatoshis = self.selectedFeeRatePerVb().feeSats(forVsize: self.sendVC!.confirmTxSize)
        
        // Double-check transaction details.
        self.showAlert(title: Language.getWord(withID: "sendtransaction"), message: Language.getWord(withID: "sendconfirmation").replacingOccurrences(of: "<amount>", with: "\(self.sendVC!.confirmSatoshis)".addSpaces()).replacingOccurrences(of: "<fees>", with: "\(feeSatoshis)".addSpaces()).replacingOccurrences(of: "<address>", with: self.sendVC!.confirmAddress), buttons: [.dismiss(Language.getWord(withID: "cancel")), .action(Language.getWord(withID: "confirm")) { self.performOnchainTransaction() }])
    }
    
    func performOnchainTransaction() {
        if self.confirmSpinner.isAnimating { return }
        
        // Start spinner.
        self.confirmLabel.alpha = 0
        self.confirmSpinner.startAnimating()
        
        // Get fees (minimum 1 sat/Vbyte).
        let feeRateSatVb = self.selectedFeeRatePerVb().wholeSatPerVb
        let isSendingMaximum = self.sendVC!.isSendingMaximum
        let address = self.sendVC!.confirmAddress
        let amountSats = UInt64(self.sendVC!.confirmSatoshis)
        
        // Broadcast transaction.
        DispatchQueue.global(qos: .userInitiated).async {
            
            let txid:String
            do {
                if isSendingMaximum {
                    txid = try BitcoinManager.shared.sendAllOnchainPayment(address: address, feeRateSatVb: feeRateSatVb)
                } else {
                    txid = try BitcoinManager.shared.sendOnchainPayment(address: address, amountSats: amountSats, feeRateSatVb: feeRateSatVb)
                }
            } catch {
                Log.info("Transaction error: \(error.localizedDescription)")
                // Unwrap LDKNode errors to their human-readable detail.
                let errorMessage:String = {
                    if let nodeError = error as? NodeError {
                        return "\(handleNodeError(nodeError).detail)"
                    } else {
                        return error.localizedDescription
                    }
                }()
                
                DispatchQueue.main.async {
                    self.confirmLabel.alpha = 1
                    self.confirmSpinner.stopAnimating()
                    self.showAlert(title: Language.getWord(withID: "error"), message: Language.getWord(withID: "transactionerror") + ": " + errorMessage, buttons: [.dismiss(Language.getWord(withID: "okay"))])
                    SentryManager.capture(error, context: "SendOnchain row 349")
                    SentryManager.countMetric("onchain.transaction.failure.2")
                }
                return
            }
            Log.debug("Transaction ID: \(txid)")
            
            try? BitcoinManager.shared.syncWallets()
            let payment = BitcoinManager.shared.listPayments().first { $0.kind.transactionID == txid }
            
            DispatchQueue.main.async {
                Log.info("Successful transaction.")
                SentryManager.countMetric("onchain.transaction.success")
                self.confirmLabel.alpha = 1
                self.confirmSpinner.stopAnimating()
                self.newTxId = txid

                if let payment = payment {
                    Log.info("Transaction is available. Launch TransactionVC.")
                    self.sendVC?.addNewPaymentToTable(thisPayment: payment)
                } else {
                    Log.info("Transaction not yet available, show alert.")
                    self.showAlert(title: Language.getWord(withID: "success"), message: Language.getWord(withID: "transactionsuccess"), buttons: [.action(Language.getWord(withID: "okay")) { self.wrapupOnchainTransaction() }])
                }
            }
        }
    }
    
    func wrapupOnchainTransaction() {
        BitcoinManager.shared.lightSync() { _ in }
        self.sendVC!.resetFields()
        self.sendVC!.slideFromConfirmToSend()
    }
}

extension UIViewController {
    
    func getMaximumSendableSats(toAddress:String? = nil, satPerVb:UInt64) -> Int? {
        
        do {
            let sendable = try BitcoinManager.shared.maximumSendableOnchainSats(toAddress: toAddress, satPerVb: satPerVb)
            return Int(sendable)
        } catch {
            Log.info("Could not compute maximum sendable amount: \(error.localizedDescription)")
            
            if let bdkError = error as? BitcoinDevKit.CreateTxError {
                switch bdkError {
                case .CoinSelection, .InsufficientFunds:
                    if BitcoinManager.shared.bittrWallet.satoshisOnchain > 0 {
                        Log.info("BDK looks stale (LDK Node onchain balance: \(BitcoinManager.shared.bittrWallet.satoshisOnchain), BDK rejected the drain).")
                    }
                default:
                    SentryManager.capture(error, context: "getMaximumSendableSats")
                }
            }
            return nil
        }
    }
    
}
