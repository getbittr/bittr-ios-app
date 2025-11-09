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
import LDKNodeFFI
import LightningDevKit
import Sentry

extension SendViewController {
    
    func checkSendOnchain() {
        // Slide from leftmost to rightmost scroll view.
        
        if self.checkInternetConnection() {
            // Set invoice text from text field.
            let invoiceText = self.toTextField.text
            
            // Check for LNURL address.
            if invoiceText != nil, invoiceText!.lowercased().contains("lnurl") {
                // Handle LNURL.
                self.confirmLightningTransaction(lnurlinvoice: invoiceText!, sendVC: self, receiveVC: nil, lnurlNote: nil)
                return
            }
            
            // Transfer to bitcoin.
            var divideBy:CGFloat
            switch self.selectedCurrency {
            case .bitcoin: divideBy = 1
            case .satoshis: divideBy = 100000000
            case .currency: divideBy = self.getCorrectBitcoinValue(coreVC: self.coreVC!).currentValue
            }
            self.onchainAmountInSatoshis = (self.amountTextField.text!.toNumber()/divideBy).inSatoshis()
            
            if invoiceText == nil || invoiceText?.trimmingCharacters(in: .whitespaces) == "" || self.amountTextField.text == nil || self.amountTextField.text?.trimmingCharacters(in: .whitespacesAndNewlines) == "" || self.onchainAmountInSatoshis == 0  {
                
                // Fields are left empty or the amount is set to zero.
                var errorMessage = ""
                if invoiceText == nil || invoiceText?.trimmingCharacters(in: .whitespaces) == "" {
                    errorMessage = Language.getWord(withID: "enteraddress")
                } else if self.amountTextField.text == nil || self.amountTextField.text?.trimmingCharacters(in: .whitespacesAndNewlines) == "" || self.onchainAmountInSatoshis == 0 {
                    errorMessage = Language.getWord(withID: "enteramount")
                }
                self.showAlert(presentingController: self, title: Language.getWord(withID: "oops"), message: errorMessage, buttons: [Language.getWord(withID: "okay")], actions: nil)
                
            } else if self.onchainAmountInSatoshis > self.coreVC!.bittrWallet.satoshisOnchain {
                // Check if we have sufficient Lightning balance for a swap
                let availableLightningBalance = (self.coreVC?.bittrWallet.lightningChannels.first?.outboundCapacityMsat ?? 0)/1000
                
                print("DEBUG - Onchain payment validation:")
                print("  - btcAmount: \(self.coreVC!.bittrWallet.satoshisOnchain.inBTC())")
                print("  - onchainAmountInSatoshis: \(self.onchainAmountInSatoshis)")
                print("  - maximumSendableLNSats: \((self.coreVC?.bittrWallet.lightningChannels.first?.outboundCapacityMsat ?? 0)/1000)")
                print("  - satoshisLightning: \(self.coreVC?.bittrWallet.satoshisLightning ?? -1)")
                print("  - availableLightningBalance: \(availableLightningBalance)")
                print("  - Is Lightning balance sufficient? \(availableLightningBalance >= self.onchainAmountInSatoshis)")
                
                if availableLightningBalance >= self.onchainAmountInSatoshis {
                    print("DEBUG - Offering Lightning swap option")
                    print("DEBUG - Setting pendingOnchainAddress for swap: \(invoiceText ?? "nil")")
                    print("DEBUG - onchainAmountInSatoshis: \(self.onchainAmountInSatoshis)")
                    // Suggest swap from Lightning to onchain
                    self.showAlert(
                        presentingController: self, 
                        title: Language.getWord(withID: "insufficientfunds"), 
                        message: Language.getWord(withID: "onchaininsufficientfunds").replacingOccurrences(of: "<amount>", with: String(self.coreVC!.bittrWallet.satoshisOnchain)) + "\n\n" + Language.getWord(withID: "swapinsufficientfundslightning").replacingOccurrences(of: "<amount>", with: "\(availableLightningBalance)"),
                        buttons: [Language.getWord(withID: "cancel"), Language.getWord(withID: "swapandpay")],
                        actions: [#selector(self.cancelSwapOffer), #selector(self.swapAndPayOnchain)]
                    )
                    // Store the address for the swap
                    self.pendingOnchainAddress = invoiceText!
                    print("DEBUG - pendingOnchainAddress is now: \(self.pendingOnchainAddress)")
                } else {
                    print("DEBUG - Lightning balance insufficient, showing regular insufficient funds message")
                    // Insufficient funds in both onchain and Lightning
                    self.showAlert(presentingController: self, title: Language.getWord(withID: "oops"), message: Language.getWord(withID: "spendablebalance"), buttons: [Language.getWord(withID: "okay")], actions: nil)
                }
            } else {
                // Start button animation.
                self.nextLabel.alpha = 0
                self.arrowIcon.alpha = 0
                self.nextSpinner.startAnimating()
                
                // Set confirmation labels.
                let bitcoinValue = self.getCorrectBitcoinValue(coreVC: self.coreVC!)
                self.confirmAddressLabel.text = invoiceText
                self.confirmAmountLabel.text = "\(formatBitcoinAmount(self.onchainAmountInSatoshis.inBTC())) BTC"
                self.confirmEuroLabel.text = "\(Int(self.onchainAmountInSatoshis.inBTC()*bitcoinValue.currentValue)) \(bitcoinValue.chosenCurrency)"
                
                // Create transaction.
                if let actualWallet = LightningNodeService.shared.getWallet() {
                    let actualAddress:String = invoiceText!
                    
                    Task {
                        do {
                            // Get estimated fees.
                            let feeEstimates = try LightningNodeService.shared.getEsploraClient()!.getFeeEstimates()
                            self.feeLow = Float(Int(feeEstimates[6]!*10))/10
                            self.feeMedium = Float(Int(feeEstimates[3]!*10))/10
                            self.feeHigh = Float(Int(feeEstimates[1]!*10))/10
                            
                            // Get transaction size.
                            let size = try self.getSize(address: actualAddress, amountSats: self.onchainAmountInSatoshis, wallet: actualWallet)
                            print("High: \(self.feeHigh*Float(size)), Medium: \(self.feeMedium*Float(size)), Low: \(self.feeLow*Float(size))")
                            
                            // Calculate lowest sats.
                            let lowestSats:Float = self.feeLow*Float(size)
                            let availableSatsForFee:Float = Float(self.coreVC!.bittrWallet.satoshisOnchain - self.onchainAmountInSatoshis)
                            if lowestSats > availableSatsForFee {
                                // There aren't enough sats available to pay for the cheapest fee.
                                let availableSatsPerVb:Float = availableSatsForFee / Float(size)
                                self.feeLow = Float(Int(availableSatsPerVb * 10))/10
                                
                                self.slowTimeLabel.text = "Slow"
                                self.highlightView(selectedFee: .low)
                                self.selectedFee = .low
                            } else {
                                self.slowTimeLabel.text = "1 day"
                                self.highlightView(selectedFee: .medium)
                                self.selectedFee = .medium
                            }
                            
                            // Set satoshis text.
                            self.satsFast.text = "\(Int(self.feeHigh*Float(size))) sats"
                            self.satsMedium.text = "\(Int(self.feeMedium*Float(size))) sats"
                            self.satsSlow.text = "\(Int(self.feeLow*Float(size))) sats"
                            
                            // Set converted text.
                            self.eurosFast.text = self.convertFees(transactionSize: size, satsPerVbyte: self.feeHigh, bitcoinValue: bitcoinValue) + " " + bitcoinValue.chosenCurrency
                            self.eurosMedium.text = self.convertFees(transactionSize: size, satsPerVbyte: self.feeMedium, bitcoinValue: bitcoinValue) + " " + bitcoinValue.chosenCurrency
                            self.eurosSlow.text = self.convertFees(transactionSize: size, satsPerVbyte: self.feeLow, bitcoinValue: bitcoinValue) + " " + bitcoinValue.chosenCurrency
                            
                            // Animation from main view to confirm view.
                            DispatchQueue.main.async {
                                UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseInOut) {
                                    NSLayoutConstraint.deactivate([self.scrollViewTrailing])
                                    self.scrollViewTrailing = NSLayoutConstraint(item: self.scrollView, attribute: .trailing, relatedBy: .equal, toItem: self.view, attribute: .leading, multiplier: 1, constant: 0)
                                    NSLayoutConstraint.activate([self.scrollViewTrailing])
                                    self.view.layoutIfNeeded()
                                }
                                self.nextLabel.alpha = 1
                                self.arrowIcon.alpha = 1
                                self.nextSpinner.stopAnimating()
                            }
                        } catch {
                            print("Error: \(error.localizedDescription)")
                            
                            // Generate error message.
                            var errorMessage = error.localizedDescription
                            if let bdkError = error as? BitcoinDevKit.CreateTxError {
                                errorMessage = bdkError.getErrorMessage()
                            } else if let bdkError = error as? BitcoinDevKit.AddressParseError {
                                errorMessage = bdkError.getErrorMessage()
                            }
                            
                            // Show alert.
                            DispatchQueue.main.async {
                                self.nextLabel.alpha = 1
                                self.arrowIcon.alpha = 1
                                self.nextSpinner.stopAnimating()
                                self.showAlert(presentingController: self, title: Language.getWord(withID: "oops"), message: "\(Language.getWord(withID: "cannotproceed")). Error: \(errorMessage)", buttons: [Language.getWord(withID: "okay")], actions: nil)
                                SentrySDK.capture(error: error) { scope in
                                    scope.setExtra(value: "SendOnchain row 167", key: "context")
                                }
                            }
                        }
                    }
                }
            }
        } else {
            self.showAlert(presentingController: self, title: Language.getWord(withID: "checkyourconnection"), message: Language.getWord(withID: "trytoconnect"), buttons: [Language.getWord(withID: "okay")], actions: nil)
        }
    }
    
    func convertFees(transactionSize:UInt64, satsPerVbyte:Float, bitcoinValue:BitcoinValue) -> String {
        let satsValue = CGFloat(satsPerVbyte*Float(transactionSize))
        var satsText = "\(CGFloat(Int((satsValue.inBTC()*bitcoinValue.currentValue)*100))/100)"
        if String(satsText.fixDecimals().split(separator: Locale.current.decimalSeparator!)[1]).count == 1 {
            satsText = satsText + "0"
        }
        return satsText
    }
    
    func switchFeeSelection(tappedFee:SelectedFee) {
        // Switch selected fee rate.
        
        switch tappedFee {
        case .high:
            let feeInSats = Int(self.satsFast.text!.replacingOccurrences(of: " sats", with: "").toNumber())
            self.selectedFeeInSats = feeInSats
            
            if self.checkFeeAvailability(feeInSats: feeInSats, actualAmount: self.onchainAmountInSatoshis, availableBalance: self.coreVC!.bittrWallet.satoshisOnchain) {
                self.highlightView(selectedFee: .high)
                self.checkHighFeeRate(satsText: self.satsFast.text!)
            }
        case .medium:
            let feeInSats = Int(self.satsMedium.text!.replacingOccurrences(of: " sats", with: "").toNumber())
            self.selectedFeeInSats = feeInSats
            
            if self.checkFeeAvailability(feeInSats: feeInSats, actualAmount: self.onchainAmountInSatoshis, availableBalance: self.coreVC!.bittrWallet.satoshisOnchain) {
                self.highlightView(selectedFee: .medium)
                self.checkHighFeeRate(satsText: self.satsMedium.text!)
            }
        case .low:
            self.highlightView(selectedFee: .low)
            self.checkHighFeeRate(satsText: self.satsSlow.text!)
        }
    }
    
    func highlightView(selectedFee:SelectedFee) {
        self.selectedFee = selectedFee
        switch selectedFee {
        case .low:
            self.fastView.backgroundColor = Colors.getColor("white0.7orblue2")
            self.mediumView.backgroundColor = Colors.getColor("white0.7orblue2")
            self.slowView.backgroundColor = Colors.getColor("whiteorblue3")
        case .medium:
            self.fastView.backgroundColor = Colors.getColor("white0.7orblue2")
            self.mediumView.backgroundColor = Colors.getColor("whiteorblue3")
            self.slowView.backgroundColor = Colors.getColor("white0.7orblue2")
        case .high:
            self.fastView.backgroundColor = Colors.getColor("whiteorblue3")
            self.mediumView.backgroundColor = Colors.getColor("white0.7orblue2")
            self.slowView.backgroundColor = Colors.getColor("white0.7orblue2")
        }
    }
    
    func checkHighFeeRate(satsText:String) {
        // Check if selected fee rate is too high.
        if satsText.replacingOccurrences(of: " sats", with: "").toNumber() / CGFloat(self.onchainAmountInSatoshis) > 0.1 {
            self.showAlert(presentingController: self, title: Language.getWord(withID: "highfeerate"), message: Language.getWord(withID: "highfeerate2"), buttons: [Language.getWord(withID: "okay")], actions: nil)
        }
    }
    
    func checkFeeAvailability(feeInSats:Int, actualAmount:Int, availableBalance:Int) -> Bool {
        
        if feeInSats + actualAmount > availableBalance {
            self.showAlert(presentingController: self, title: Language.getWord(withID: "balance2"), message: "\(Language.getWord(withID: "youravailablebalance")) (\(availableBalance) sats) \(Language.getWord(withID: "isinsufficient")).", buttons: [Language.getWord(withID: "updateamount"), Language.getWord(withID: "close")], actions: [#selector(self.handleAmountChange), nil])
            return false
        } else {
            return true
        }
    }
    
    @objc func handleAmountChange() {
        self.hideAlert()
        
        self.amountTextField.text = "\((self.coreVC!.bittrWallet.satoshisOnchain-self.selectedFeeInSats).inBTC())".replacingOccurrences(of: "00000000001", with: "").replacingOccurrences(of: "99999999999", with: "").replacingOccurrences(of: "0000000001", with: "").replacingOccurrences(of: "9999999999", with: "")
        
        let bitcoinValue = self.getCorrectBitcoinValue(coreVC: self.coreVC!)
        self.confirmAmountLabel.text = "\(formatBitcoinAmount(self.onchainAmountInSatoshis.inBTC())) BTC"
        self.confirmEuroLabel.text = "\(Int(self.onchainAmountInSatoshis.inBTC()*bitcoinValue.currentValue)) \(bitcoinValue.chosenCurrency)"
        
        self.switchFeeSelection(tappedFee:self.selectedFee)
    }
    
    func confirmSendOnchain() {
        // Send onchain transaction.
        // Check whether selected fee is appropriate.
        
        if self.slowTimeLabel.text == "Slow" && self.selectedFee == .low {
            // Selected fee is very low.
            self.showAlert(presentingController: self, title: Language.getWord(withID: "lowfee"), message: Language.getWord(withID: "lowfee2"), buttons: [Language.getWord(withID: "changefee"), Language.getWord(withID: "continue")], actions: [nil, #selector(self.proceedWithOnchainConfirmation)])
        } else {
            self.proceedWithOnchainConfirmation()
        }
    }
    
    @objc func proceedWithOnchainConfirmation() {
        self.hideAlert()
        
        var feeSatoshis:String
        switch self.selectedFee {
        case .low: feeSatoshis = (self.satsSlow.text ?? "no").replacingOccurrences(of: " sats", with: "")
        case .medium: feeSatoshis = (self.satsMedium.text ?? "no").replacingOccurrences(of: " sats", with: "")
        case .high: feeSatoshis = (self.satsFast.text ?? "no").replacingOccurrences(of: " sats", with: "")
        }
        
        self.showAlert(
            presentingController: self,
            title: Language.getWord(withID: "sendtransaction"),
            message: Language.getWord(withID: "sendconfirmation")
                .replacingOccurrences(of: "<amount>", with: "\(self.onchainAmountInSatoshis.inBTC())")
                .replacingOccurrences(of: "<fees>", with: feeSatoshis)
                .replacingOccurrences(of: "<address>", with: self.confirmAddressLabel.text ?? Language.getWord(withID: "thisaddress")),
            buttons: [Language.getWord(withID: "cancel"), Language.getWord(withID: "confirm")],
            actions: [nil, #selector(self.performOnchainTransaction)]
        )
    }
    
    @objc func performOnchainTransaction() {
        self.hideAlert()
        
        // Start spinner.
        self.sendLabel.alpha = 0
        self.sendSpinner.startAnimating()
        
        // Get wallet.
        if let actualWallet = LightningNodeService.shared.getWallet() {
            
            // Get address.
            let actualAddress:String = self.confirmAddressLabel.text!
            
            // Get fees.
            var selectedVbyte:Float
            switch self.selectedFee {
            case .low: selectedVbyte = self.feeLow
            case .medium: selectedVbyte = self.feeMedium
            case .high: selectedVbyte = self.feeHigh
            }
            
            // Create transaction.
            Task {
                do {
                    let tx = try self.getTx(address: actualAddress, amountSats: self.onchainAmountInSatoshis, wallet: actualWallet, selectedVbyte: selectedVbyte)
                    if let client = LightningNodeService.shared.getClient() {
                        
                        // Broadcast transaction.
                        let txid = try client.transactionBroadcast(tx: tx)
                        print("Transaction ID: \(txid)")
                        
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            print("Successful transaction.")
                            SentrySDK.metrics.increment(key: "onchain.transaction.success")
                            self.sendLabel.alpha = 1
                            self.sendSpinner.stopAnimating()
                            self.newTxId = txid
                            
                            self.showAlert(presentingController: self, title: Language.getWord(withID: "success"), message: Language.getWord(withID: "transactionsuccess"), buttons: [Language.getWord(withID: "okay")], actions: [#selector(self.addNewTxToTable)])
                        }
                    } else {
                        DispatchQueue.main.async {
                            print("Client not available.")
                            self.sendLabel.alpha = 1
                            self.sendSpinner.stopAnimating()
                            self.showAlert(presentingController: self, title: Language.getWord(withID: "error"), message: Language.getWord(withID: "transactionerror2"), buttons: [Language.getWord(withID: "okay")], actions: nil)
                            SentrySDK.metrics.increment(key: "onchain.transaction.failure.3")
                        }
                    }
                } catch {
                    print("Transaction error: \(error.localizedDescription)")
                    DispatchQueue.main.async {
                        self.sendLabel.alpha = 1
                        self.sendSpinner.stopAnimating()
                        self.showAlert(presentingController: self, title: Language.getWord(withID: "error"), message: "\(Language.getWord(withID: "transactionerror")): \(error.localizedDescription).", buttons: [Language.getWord(withID: "okay")], actions: nil)
                        SentrySDK.capture(error: error) { scope in
                            scope.setExtra(value: "SendOnchain row 349", key: "context")
                        }
                        SentrySDK.metrics.increment(key: "onchain.transaction.failure.2")
                    }
                }
            }
        } else {
            print("Wallet instance not available.")
            SentrySDK.metrics.increment(key: "onchain.transaction.failure.1")
            self.sendLabel.alpha = 1
            self.sendSpinner.stopAnimating()
            self.showAlert(presentingController: self, title: Language.getWord(withID: "error"), message: Language.getWord(withID: "transactionerror2"), buttons: [Language.getWord(withID: "okay")], actions: nil)
        }
    }
    
    @objc func addNewTxToTable() {
        self.hideAlert()
        
        LightningNodeService.shared.lightSync() { success in
            if success, self.coreVC?.bittrWallet.transactionsOnchain != nil {
                for eachTransaction in self.coreVC!.bittrWallet.transactionsOnchain! {
                    if eachTransaction.transaction.computeTxid() == self.newTxId {
                        self.completedTransaction = eachTransaction.createTransaction(coreVC: self.coreVC!, bittrTransactions: nil)
                        self.performSegue(withIdentifier: "SendToTransaction", sender: self)
                    }
                }
            }
        }
        
        self.resetFields()
        // Slide back to leftmost scroll view.
        UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseInOut) {
            NSLayoutConstraint.deactivate([self.scrollViewTrailing])
            self.scrollViewTrailing = NSLayoutConstraint(item: self.scrollView, attribute: .trailing, relatedBy: .equal, toItem: self.view, attribute: .trailing, multiplier: 1, constant: 0)
            NSLayoutConstraint.activate([self.scrollViewTrailing])
            self.view.layoutIfNeeded()
        }
    }
    
    func getMaximumSendableSats(coreVC:CoreViewController) -> Double? {
        
        if let actualWallet = LightningNodeService.shared.getWallet() {
            do {
                let actualAddress:String = actualWallet.peekAddress(keychain: .external, index: 0).address.description
                _ = try self.getPsbt(address: actualAddress, amountSats: coreVC.bittrWallet.satoshisOnchain, wallet: actualWallet, selectedVbyte: nil)
                return nil
            } catch {
                if let bdkError = error as? BitcoinDevKit.CreateTxError {
                    switch bdkError {
                    case .InsufficientFunds(needed: let needed, available: _):
                        let btcOnchain = self.coreVC!.bittrWallet.satoshisOnchain.inBTC()
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
                            let btcOnchain = self.coreVC!.bittrWallet.satoshisOnchain.inBTC()
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
        } else {
            return nil
        }
    }
    
    @objc override func cancelSwapOffer() {
        self.hideAlert()
        print("DEBUG - cancelSwapOffer called, clearing pending data")
        // Clear the pending data when user cancels the swap offer
        self.pendingOnchainAddress = ""
        // Also clear the amount field to make it obvious this is cancelled
        self.amountTextField.text = ""
    }
    
    @objc func swapAndPayOnchain() {
        self.hideAlert()
        print("DEBUG - swapAndPayOnchain called")
        print("DEBUG - pendingOnchainAddress: \(self.pendingOnchainAddress)")
        print("DEBUG - onchainAmountInSatoshis: \(self.onchainAmountInSatoshis)")
        // Navigate to swap screen with the pending address using existing segue pattern
        if let homeVC = self.coreVC?.homeVC {
            // Store the pending address in a way that can be accessed by the swap screen
            let pendingAddress = self.pendingOnchainAddress
            let pendingAmount = self.onchainAmountInSatoshis
            print("DEBUG - Passing to MoveViewController: address=\(pendingAddress), amount=\(pendingAmount)")
            // First dismiss the current view controller
            self.dismiss(animated: true) {
                // Then navigate through the existing segue pattern
                homeVC.performSegue(withIdentifier: "HomeToMove", sender: homeVC)
                
                // After a short delay, trigger the swap button tap to go directly to swap
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    if let moveVC = homeVC.presentedViewController as? MoveViewController {
                        // Set a flag to indicate this is from an onchain payment
                        moveVC.isFromOnchainPayment = true
                        moveVC.pendingOnchainAddress = pendingAddress
                        moveVC.pendingOnchainAmount = pendingAmount
                        moveVC.performSegue(withIdentifier: "MoveToSwap", sender: moveVC)
                    }
                }
            }
        }
    }
}

extension String {
    
    func toNumber() -> CGFloat {
        
        let formatter = NumberFormatter()
        formatter.decimalSeparator = Locale.current.decimalSeparator!
        
        if formatter.number(from: self.fixDecimals()) == nil {
            return 0
        } else {
            return CGFloat(truncating: formatter.number(from: self.fixDecimals())!)
        }
    }
}

extension UIViewController {
    
    func getSize(address:String, amountSats:Int, wallet:BitcoinDevKit.Wallet) throws -> UInt64 {
        
        let tx = try self.getTx(address: address, amountSats: amountSats, wallet: wallet, selectedVbyte: nil)
        let size = tx.vsize()
        
        return size
    }
    
    func getTx(address:String, amountSats:Int, wallet:BitcoinDevKit.Wallet, selectedVbyte:Float?) throws -> BitcoinDevKit.Transaction {
        
        let details = try self.getPsbt(address: address, amountSats: amountSats, wallet: wallet, selectedVbyte: selectedVbyte)
        let tx = try details.extractTx()
        
        return tx
    }
    
    func getPsbt(address:String, amountSats:Int, wallet:BitcoinDevKit.Wallet, selectedVbyte:Float?) throws -> BitcoinDevKit.Psbt {
        
        let network = EnvironmentConfig.bitcoinDevKitNetwork
        let address = try Address(address: address, network: network)
        let script = address.scriptPubkey()
        var txBuilder = TxBuilder().addRecipient(script: script, amount: BitcoinDevKit.Amount.fromSat(satoshi: UInt64(amountSats)))
        if selectedVbyte != nil {
            txBuilder = txBuilder.feeRate(feeRate: try FeeRate.fromSatPerVb(satVb: UInt64(selectedVbyte!)))
        }
        let details = try txBuilder.finish(wallet: wallet)
        let _ = try wallet.sign(psbt: details, signOptions: nil)
        
        return details
    }
    
}

extension Int {
    func inBTC() -> CGFloat {
        return (CGFloat(self) / 100_000_000)
    }
}

extension CGFloat {
    func inSatoshis() -> Int {
        // Safety check for invalid values
        guard self.isFinite && !self.isNaN else {
            print("⚠️ Warning: Invalid CGFloat value (\(self)) in inSatoshis()")
            return 0
        }
        
        // Use direct multiplication to avoid precision issues with Decimal
        let satoshis = self * 100_000_000
        return Int(satoshis.rounded())
    }
    
    func inBTC() -> CGFloat {
        return (self / 100_000_000)
    }
}
