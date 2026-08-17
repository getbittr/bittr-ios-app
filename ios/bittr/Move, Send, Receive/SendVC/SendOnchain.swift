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
        let enteredAddress = (self.toTextField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if enteredAddress.isEmpty {
            self.showAlert(presentingController: self, title: Language.getWord(withID: "oops"), message: Language.getWord(withID: "enteraddress"), buttons: [Language.getWord(withID: "okay")], actions: nil)
            return
        }
        
        // Check amount.
        let enteredAmount = (self.amountTextField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if enteredAmount.isEmpty {
            self.showAlert(presentingController: self, title: Language.getWord(withID: "oops"), message: Language.getWord(withID: "enteramount"), buttons: [Language.getWord(withID: "okay")], actions: nil)
            return
        }
        
        // Check for LNURL address.
        if enteredAddress.lowercased().contains("lnurl") || enteredAddress.lowercased().isValidEmail() {
            // Handle LNURL.
            self.confirmLightningTransaction(lnurlinvoice: enteredAddress, lnurlNote: nil)
            return
        }
        
        // Convert the entered amount to satoshis.
        guard let enteredSatoshis = self.getSatoshisFrom(enteredAmount: enteredAmount) else { return }
        guard enteredSatoshis > 0 else {
            self.showAlert(presentingController: self, title: Language.getWord(withID: "oops"), message: Language.getWord(withID: "enteramount"), buttons: [Language.getWord(withID: "okay")], actions: nil)
            return
        }
        self.onchainAmountInSatoshis = enteredSatoshis
        
        // Check whether user intends to empty their onchain funds.
        if let quotedMaximum = self.maximumSendableOnchainSats, self.onchainAmountInSatoshis == quotedMaximum {
            // The entered amount matches the maximum sendable onchain funds.
            self.didTapAvailable = true
        }
        
        // Check balance.
        guard self.onchainAmountInSatoshis <= (BitcoinManager.shared.bittrWallet.satoshisOnchainSpendable ?? 0) else {
            Log.info("Insufficient onchain balance.")
            Log.info("Check if we have sufficient Lightning balance for a swap.")
            
            let availableLightningBalance = (BitcoinManager.shared.bittrWallet.lightningChannels.getActiveChannel()?.outboundCapacityMsat ?? 0)/1000
            
            if availableLightningBalance >= self.onchainAmountInSatoshis {
                Log.info("Offering Lightning swap option.")
                
                self.showAlert(
                    presentingController: self,
                    title: Language.getWord(withID: "insufficientfunds"),
                    message: Language.getWord(withID: "onchaininsufficientfunds").replacingOccurrences(of: "<amount>", with: String(BitcoinManager.shared.bittrWallet.satoshisOnchain).addSpaces()) + "\n\n" + Language.getWord(withID: "swapinsufficientfundslightning").replacingOccurrences(of: "<amount>", with: "\(availableLightningBalance)".addSpaces()),
                    buttons: [Language.getWord(withID: "cancel"), Language.getWord(withID: "swapandpay")],
                    actions: [#selector(self.cancelSwapOffer), #selector(self.swapAndPayOnchain)]
                )
                // Store the address for the swap
                self.pendingOnchainAddress = enteredAddress
                
            } else {
                Log.info("Lightning balance insufficient, showing regular insufficient funds message.")
                self.showAlert(presentingController: self, title: Language.getWord(withID: "oops"), message: Language.getWord(withID: "spendablebalance"), buttons: [Language.getWord(withID: "okay")], actions: nil)
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
        self.confirmSatoshis = self.onchainAmountInSatoshis
        
        // Create transaction.
        Task {
            guard let feeEstimates = await BitcoinManager.shared.getFeeEstimates() else {
                DispatchQueue.main.async {
                    self.nextLabel.alpha = 1
                    self.arrowIcon.alpha = 1
                    self.nextSpinner.stopAnimating()
                    self.showAlert(presentingController: self, title: Language.getWord(withID: "oops"), message: "\(Language.getWord(withID: "cannotproceed")). Error: Couldn't fetch recommended fees.", buttons: [Language.getWord(withID: "okay")], actions: nil)
                }
                return
            }
            self.feePerVbLow = feeEstimates.economy
            self.feePerVbMedium = feeEstimates.hour
            self.feePerVbHigh = feeEstimates.fastest
            
            // Check the maximum sendable onchain amount.
            let drain = try? BitcoinManager.shared.maximumSendableOnchainDrain(toAddress: enteredAddress, satPerVb: self.feePerVbMedium.wholeSatPerVb)
            
            // Check whether the user intends to empty their onchain funds —
            // either by tapping the quoted maximum, or by typing an amount at or
            // above it (the balance guard above only rejects amounts over the
            // spendable balance, and the drain maximum sits a fee below that).
            //
            // Either way, restate the amount as the drain figure. sendAllToAddress
            // ignores confirmSatoshis and sends whatever is left after the fee, so
            // leaving the typed amount in place would let the confirmation screen
            // promise a number the wallet never broadcasts.
            if let drain = drain, self.didTapAvailable || self.onchainAmountInSatoshis >= Int(drain.sendableSats) {
                self.onchainAmountInSatoshis = Int(drain.sendableSats)
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
                    size = try BitcoinManager.shared.getSize(address: enteredAddress, amountSats: self.onchainAmountInSatoshis, selectedVbyte: self.feePerVbMedium)
                }
            } catch {
                Log.info("Error: \(error.localizedDescription)")
                
                // Generate error message.
                var sendToSentry = true
                var errorMessage = error.localizedDescription
                if let bdkError = error as? BitcoinDevKit.CreateTxError {
                    errorMessage = bdkError.getErrorMessage()
                    switch bdkError {
                    case .CoinSelection(errorMessage: _): sendToSentry = false
                    default: sendToSentry = true
                    }
                } else if let bdkError = error as? BitcoinDevKit.AddressParseError {
                    errorMessage = bdkError.getErrorMessage()
                }
                
                // Show alert.
                DispatchQueue.main.async {
                    self.nextLabel.alpha = 1
                    self.arrowIcon.alpha = 1
                    self.nextSpinner.stopAnimating()
                    self.showAlert(presentingController: self, title: Language.getWord(withID: "oops"), message: "\(Language.getWord(withID: "cannotproceed")). Error: \(errorMessage)", buttons: [Language.getWord(withID: "okay")], actions: nil)
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
    
    @objc func cancelSwapOffer() {
        self.hideAlert()
        // Clear the pending data when user cancels the swap offer
        self.pendingOnchainAddress = ""
        // Also clear the amount field to make it obvious this is cancelled
        self.amountTextField.text = ""
    }
    
    @objc func swapAndPayOnchain() {
        self.hideAlert()
        Log.info("swapAndPayOnchain called.")
        
        self.performSegue(withIdentifier: "SendToSwap", sender: self)
    }
}

extension ConfirmSendViewController {
    
    @objc func proceedWithOnchainConfirmation() {
        self.hideAlert()
        
        let feeSatoshis = self.selectedFeeRatePerVb().feeSats(forVsize: self.sendVC!.confirmTxSize)
        
        // Double-check transaction details.
        self.showAlert(presentingController: self, title: Language.getWord(withID: "sendtransaction"), message: Language.getWord(withID: "sendconfirmation").replacingOccurrences(of: "<amount>", with: "\(self.sendVC!.confirmSatoshis)".addSpaces()).replacingOccurrences(of: "<fees>", with: "\(feeSatoshis)".addSpaces()).replacingOccurrences(of: "<address>", with: self.sendVC!.confirmAddress), buttons: [Language.getWord(withID: "cancel"), Language.getWord(withID: "confirm")], actions: [nil, #selector(self.performOnchainTransaction)])
    }
    
    @objc func performOnchainTransaction() {
        self.hideAlert()
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
                    self.showAlert(presentingController: self, title: Language.getWord(withID: "error"), message: Language.getWord(withID: "transactionerror") + ": " + errorMessage, buttons: [Language.getWord(withID: "okay")], actions: nil)
                    SentryManager.capture(error, context: "SendOnchain row 349")
                    SentryManager.countMetric("onchain.transaction.failure.2")
                }
                return
            }
            Log.debug("Transaction ID: \(txid)")
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                Log.info("Successful transaction.")
                SentryManager.countMetric("onchain.transaction.success")
                self.confirmLabel.alpha = 1
                self.confirmSpinner.stopAnimating()
                self.newTxId = txid

                self.showAlert(presentingController: self, title: Language.getWord(withID: "success"), message: Language.getWord(withID: "transactionsuccess"), buttons: [Language.getWord(withID: "okay")], actions: [#selector(self.addNewTxToTable)])
            }
        }
    }
    
    @objc func addNewTxToTable() {
        self.hideAlert()
        
        BitcoinManager.shared.lightSync() { success in
            if success {
                for eachTransaction in BitcoinManager.shared.bittrWallet.allTransactions {
                    if eachTransaction.kind.transactionID == self.newTxId {
                        self.sendVC!.completedTransaction = eachTransaction.createTransaction(bittrTransactions: nil)
                        self.sendVC!.performSegue(withIdentifier: "SendToTransaction", sender: self)
                    }
                }
            }
        }
        
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
