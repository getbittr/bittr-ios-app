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
import Sentry

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
        let enteredAmount = (self.amountTextField.text ?? "0").toNumber()
        if enteredAmount == 0 {
            self.showAlert(presentingController: self, title: Language.getWord(withID: "oops"), message: Language.getWord(withID: "enteramount"), buttons: [Language.getWord(withID: "okay")], actions: nil)
            return
        }
        
        // Check for LNURL address.
        if enteredAddress.lowercased().contains("lnurl") || enteredAddress.lowercased().isValidEmail() {
            // Handle LNURL.
            self.confirmLightningTransaction(lnurlinvoice: enteredAddress, lnurlNote: nil)
            return
        }
        
        // Transfer to bitcoin.
        var divideBy:CGFloat
        switch self.selectedCurrency {
        case .bitcoin: divideBy = 1
        case .satoshis: divideBy = 100000000
        case .currency: divideBy = BitcoinManager.shared.bittrWallet.getCorrectBitcoinValue().currentValue
        }
        self.onchainAmountInSatoshis = (enteredAmount/divideBy).inSatoshis()
        
        // Check balance.
        guard self.onchainAmountInSatoshis <= BitcoinManager.shared.bittrWallet.satoshisOnchain else {
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
            let feeEstimates = await BitcoinManager.shared.getFeeEstimates()
            guard feeEstimates != nil else {
                DispatchQueue.main.async {
                    self.nextLabel.alpha = 1
                    self.arrowIcon.alpha = 1
                    self.nextSpinner.stopAnimating()
                    self.showAlert(presentingController: self, title: Language.getWord(withID: "oops"), message: "\(Language.getWord(withID: "cannotproceed")). Error: Couldn't fetch recommended fees.", buttons: [Language.getWord(withID: "okay")], actions: nil)
                }
                return
            }
            self.feePerVbLow = Float(feeEstimates!["economyFee"] as! Double)
            self.feePerVbMedium = Float(feeEstimates!["hourFee"] as! Double)
            self.feePerVbHigh = Float(feeEstimates!["fastestFee"] as! Double)
            
            // Get transaction size.
            let size:UInt64
            do {
                size = try BitcoinManager.shared.getSize(address: enteredAddress, amountSats: self.onchainAmountInSatoshis)
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
                        SentrySDK.capture(error: error) { scope in
                            scope.setExtra(value: "SendOnchain row 167", key: "context")
                        }
                    }
                }
                return
            }
            self.confirmTxSize = Float(size)
            
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
        
        var feeSatoshis:Int
        switch self.selectedFee {
        case .medium: feeSatoshis = Int(self.sendVC!.feePerVbMedium * self.sendVC!.confirmTxSize)
        case .high: feeSatoshis = Int(self.sendVC!.feePerVbHigh * self.sendVC!.confirmTxSize)
        default: feeSatoshis = Int((self.maxAvailableFeePerVb ?? self.sendVC!.feePerVbLow) * self.sendVC!.confirmTxSize)
        }
        
        // Double-check transaction details.
        self.showAlert(presentingController: self, title: Language.getWord(withID: "sendtransaction"), message: Language.getWord(withID: "sendconfirmation").replacingOccurrences(of: "<amount>", with: "\(self.sendVC!.confirmSatoshis)".addSpaces()).replacingOccurrences(of: "<fees>", with: "\(feeSatoshis)".addSpaces()).replacingOccurrences(of: "<address>", with: self.sendVC!.confirmAddress), buttons: [Language.getWord(withID: "cancel"), Language.getWord(withID: "confirm")], actions: [nil, #selector(self.performOnchainTransaction)])
    }
    
    @objc func performOnchainTransaction() {
        self.hideAlert()
        
        // Start spinner.
        self.confirmLabel.alpha = 0
        self.confirmSpinner.startAnimating()
        
        // Get fees.
        var selectedVbyte:Float
        switch self.selectedFee {
        case .medium: selectedVbyte = self.sendVC!.feePerVbMedium
        case .high: selectedVbyte = self.sendVC!.feePerVbHigh
        default: selectedVbyte = self.maxAvailableFeePerVb ?? self.sendVC!.feePerVbLow
        }
        
        // Broadcast transaction.
        let txid:String
        do {
            txid = try BitcoinManager.shared.sendOnchainPayment(address: self.sendVC!.confirmAddress, amountSats: UInt64(self.sendVC!.confirmSatoshis), feeRateSatVb: UInt64(selectedVbyte))
        } catch {
            Log.info("Transaction error: \(error.localizedDescription)")

            // Unwrap LDKNode errors to their human-readable detail (e.g. the
            // plain "insufficient funds" message) via the shared handler,
            // instead of showing the raw NodeError enum description.
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
                SentrySDK.capture(error: error) { scope in
                    scope.setExtra(value: "SendOnchain row 349", key: "context")
                }
                SentrySDK.metrics.count(key: "onchain.transaction.failure.2")
            }
            return
        }
        print("Transaction ID: \(txid)")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            Log.info("Successful transaction.")
            SentrySDK.metrics.count(key: "onchain.transaction.success")
            self.confirmLabel.alpha = 1
            self.confirmSpinner.stopAnimating()
            self.newTxId = txid
            
            self.showAlert(presentingController: self, title: Language.getWord(withID: "success"), message: Language.getWord(withID: "transactionsuccess"), buttons: [Language.getWord(withID: "okay")], actions: [#selector(self.addNewTxToTable)])
        }
    }
    
    @objc func addNewTxToTable() {
        self.hideAlert()
        
        BitcoinManager.shared.lightSync() { success in
            if success {
                for eachTransaction in BitcoinManager.shared.bittrWallet.allTransactions {
                    if eachTransaction.kind.transactionID == self.newTxId {
                        self.sendVC!.completedTransaction = eachTransaction.createTransaction(coreVC: self.coreVC!, bittrTransactions: nil)
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
    
    func getMaximumSendableSats(coreVC:CoreViewController) -> Double? {
        
        do {
            let actualAddress = BitcoinManager.shared.getAddress(atIndex: 0)
            
            // Create PSBT, which will throw an error.
            _ = try BitcoinManager.shared.getPsbt(address: actualAddress, amountSats: BitcoinManager.shared.bittrWallet.satoshisOnchain, selectedVbyte: nil)
            return nil
        } catch {
            if let bdkError = error as? BitcoinDevKit.CreateTxError {
                switch bdkError {
                case .InsufficientFunds(needed: let needed, available: _):
                    let btcOnchain = BitcoinManager.shared.bittrWallet.satoshisOnchain.inBTC()
                    let neededAmount:Double = Int(needed).inBTC()
                    let minimumFees:Double = neededAmount - btcOnchain
                    let spendableBtcAmount = btcOnchain - minimumFees
                    if spendableBtcAmount < 0 {
                        return 0
                    } else {
                        return spendableBtcAmount
                    }
                case .CoinSelection(errorMessage: let errorMessage):
                    if errorMessage.contains("Insufficient funds") {
                        let btcOnchain = BitcoinManager.shared.bittrWallet.satoshisOnchain.inBTC()
                        let neededAmount:Double = String(error.localizedDescription.split(separator: " ")[7]).toNumber()
                        let minimumFees:Double = neededAmount - btcOnchain
                        let spendableBtcAmount = btcOnchain - minimumFees
                        if spendableBtcAmount < 0 {
                            return 0
                        } else if spendableBtcAmount > btcOnchain {
                            return nil
                        } else {
                            return spendableBtcAmount
                        }
                    } else {
                        return nil
                    }
                default: return nil
                }
            } else {
                return nil
            }
        }
    }
    
}
