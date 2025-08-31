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
            var invoiceText = self.toTextField.text
            
            if invoiceText != nil {
                if invoiceText!.lowercased().contains("lnurl") {
                    // LNURL.
                    self.confirmLightningTransaction(lnurlinvoice: invoiceText!, sendVC: self, receiveVC: nil, lnurlNote: nil)
                    return
                }
            }
            
            // Transfer to bitcoin.
            var divideBy:CGFloat = 1
            if self.selectedCurrency == "satoshis" {
                divideBy = 100000000
            } else if self.selectedCurrency == "currency" {
                divideBy = self.getCorrectBitcoinValue(coreVC: self.coreVC!).currentValue
            }
            
            self.onchainAmountInSatoshis = Int(((self.stringToNumber(self.amountTextField.text)/divideBy) * 100000000).rounded())
            self.onchainAmountInBTC = CGFloat(self.onchainAmountInSatoshis)/100000000
            
            if invoiceText == nil || invoiceText?.trimmingCharacters(in: .whitespaces) == "" || self.amountTextField.text == nil || self.amountTextField.text?.trimmingCharacters(in: .whitespacesAndNewlines) == "" || self.onchainAmountInSatoshis == 0  {
                
                // Fields are left empty or the amount if set to zero.
                var errorMessage = ""
                
                if invoiceText == nil || invoiceText?.trimmingCharacters(in: .whitespaces) == "" {
                    errorMessage = Language.getWord(withID: "enteraddress")
                } else if self.amountTextField.text == nil || self.amountTextField.text?.trimmingCharacters(in: .whitespacesAndNewlines) == "" || self.onchainAmountInSatoshis == 0 {
                    errorMessage = Language.getWord(withID: "enteramount")
                }
                
                self.showAlert(presentingController: self, title: Language.getWord(withID: "oops"), message: errorMessage, buttons: [Language.getWord(withID: "okay")], actions: nil)
                
            } else if self.onchainAmountInBTC > CGFloat(self.coreVC!.bittrWallet.satoshisOnchain)*0.00000001 {
                // Check if we have sufficient Lightning balance for a swap
                let availableLightningBalance = self.maximumSendableLNSats ?? self.homeVC?.coreVC?.bittrWallet.satoshisLightning ?? 0
                
                print("DEBUG - Onchain payment validation:")
                print("  - onchainAmountInBTC: \(self.onchainAmountInBTC)")
                print("  - btcAmount: \(CGFloat(self.coreVC!.bittrWallet.satoshisOnchain)*0.00000001)")
                print("  - onchainAmountInSatoshis: \(self.onchainAmountInSatoshis)")
                print("  - maximumSendableLNSats: \(self.maximumSendableLNSats ?? -1)")
                print("  - satoshisLightning: \(self.homeVC?.coreVC?.bittrWallet.satoshisLightning ?? -1)")
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
                        message: "\(Language.getWord(withID: "onchaininsufficientfunds")) \(self.coreVC!.bittrWallet.satoshisOnchain) satoshis.\n\n\(Language.getWord(withID: "swapinsufficientfunds")) \(availableLightningBalance) satoshis.",
                        buttons: [Language.getWord(withID: "cancel"), Language.getWord(withID: "swapandpay")],
                        actions: [#selector(self.cancelSwapOffer), #selector(self.swapAndPayOnchain)]
                    )
                    // Store the address for the swap
                    self.pendingOnchainAddress = invoiceText!
                    print("DEBUG - pendingOnchainAddress is now: \(self.pendingOnchainAddress)")
                    return
                } else {
                    print("DEBUG - Lightning balance insufficient, showing regular insufficient funds message")
                    // Insufficient funds in both onchain and Lightning
                    self.showAlert(presentingController: self, title: Language.getWord(withID: "oops"), message: Language.getWord(withID: "spendablebalance"), buttons: [Language.getWord(withID: "okay")], actions: nil)
                }
            } else {
            
                self.nextLabel.alpha = 0
                self.nextSpinner.startAnimating()
                
                let bitcoinValue = self.getCorrectBitcoinValue(coreVC: self.coreVC!)
                
                self.confirmAddressLabel.text = invoiceText
                self.confirmAmountLabel.text = "\(formatBitcoinAmount(self.onchainAmountInBTC)) BTC"
                self.confirmEuroLabel.text = "\(Int(self.onchainAmountInBTC*bitcoinValue.currentValue)) \(bitcoinValue.chosenCurrency)"
                
                if let actualWallet = LightningNodeService.shared.getWallet() {
                    
                    let actualAddress:String = invoiceText!
                    
                    Task {
                        do {
                            
                            let feeEstimates = try LightningNodeService.shared.getEsploraClient()!.getFeeEstimates()
                            
                            let high = feeEstimates[1]!
                            let medium = feeEstimates[3]!
                            let low = feeEstimates[6]!
                            
                            self.feeLow = Float(Int(low*10))/10
                            self.feeMedium = Float(Int(medium*10))/10
                            self.feeHigh = Float(Int(high*10))/10
                            
                            print("Adjusted - High: \(self.feeHigh), Medium: \(self.feeMedium), Low: \(self.feeLow)")
                            
                            let size = try self.getSize(address: actualAddress, amountSats: self.onchainAmountInSatoshis, wallet: actualWallet)

                            print("Size: \(String(describing: size))")
                            print("High: \(self.feeHigh*Float(size)), Medium: \(self.feeMedium*Float(size)), Low: \(self.feeLow*Float(size))")
                            
                            let lowestSats:Float = self.feeLow*Float(size)
                            let availableSatsForFee:Float = Float(self.coreVC!.bittrWallet.satoshisOnchain - self.onchainAmountInSatoshis)
                            if lowestSats > availableSatsForFee {
                                // There aren't enough sats available to pay for the cheapest fee.
                                let availableSatsPerVb:Float = availableSatsForFee / Float(size)
                                self.feeLow = Float(Int(availableSatsPerVb * 10))/10
                                self.slowTimeLabel.text = "Slow"
                                
                                self.fastView.backgroundColor = Colors.getColor("white0.7orblue2")
                                self.mediumView.backgroundColor = Colors.getColor("white0.7orblue2")
                                self.slowView.backgroundColor = Colors.getColor("whiteorblue3")
                                self.selectedFee = "low"
                            } else {
                                self.slowTimeLabel.text = "1 day"
                                
                                self.fastView.backgroundColor = Colors.getColor("white0.7orblue2")
                                self.mediumView.backgroundColor = Colors.getColor("whiteorblue3")
                                self.slowView.backgroundColor = Colors.getColor("white0.7orblue2")
                                self.selectedFee = "medium"
                            }
                            
                            self.satsFast.text = "\(Int(self.feeHigh*Float(size))) sats"
                            self.satsMedium.text = "\(Int(self.feeMedium*Float(size))) sats"
                            self.satsSlow.text = "\(Int(self.feeLow*Float(size))) sats"
                            
                            let fast1 = CGFloat(self.feeHigh*Float(size))
                            var fastText = "\(CGFloat(Int(((fast1/100000000)*bitcoinValue.currentValue)*100))/100)"
                            if fastText.count == 3 {
                                fastText = fastText + "0"
                            }
                            let medium1 = CGFloat(self.feeMedium*Float(size))
                            var mediumText = "\(CGFloat(Int(((medium1/100000000)*bitcoinValue.currentValue)*100))/100)"
                            if mediumText.count == 3 {
                                mediumText = mediumText + "0"
                            }
                            let slow1 = CGFloat(self.feeLow*Float(size))
                            var slowText = "\(CGFloat(Int(((slow1/100000000)*bitcoinValue.currentValue)*100))/100)"
                            if slowText.count == 3 {
                                slowText = slowText + "0"
                            }
                            
                            self.eurosFast.text = fastText + " " + bitcoinValue.chosenCurrency
                            self.eurosMedium.text = mediumText + " " + bitcoinValue.chosenCurrency
                            self.eurosSlow.text = slowText + " " + bitcoinValue.chosenCurrency
                            
                            DispatchQueue.main.async {
                                UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseInOut) {
                                    
                                    NSLayoutConstraint.deactivate([self.scrollViewTrailing])
                                    self.scrollViewTrailing = NSLayoutConstraint(item: self.scrollView, attribute: .trailing, relatedBy: .equal, toItem: self.view, attribute: .leading, multiplier: 1, constant: 0)
                                    NSLayoutConstraint.activate([self.scrollViewTrailing])
                                    self.view.layoutIfNeeded()
                                }
                                
                                self.nextLabel.alpha = 1
                                self.nextSpinner.stopAnimating()
                            }
                        } catch {
                            print("Error: \(error.localizedDescription)")
                            DispatchQueue.main.async {
                                self.nextLabel.alpha = 1
                                self.nextSpinner.stopAnimating()
                                
                                self.showAlert(presentingController: self, title: Language.getWord(withID: "oops"), message: "\(Language.getWord(withID: "cannotproceed")). Error: \(error.localizedDescription).", buttons: [Language.getWord(withID: "okay")], actions: nil)
                                
                                SentrySDK.capture(error: error)
                            }
                        }
                    }
                }
            }
        }
    }
    
    
    func switchFeeSelection(tappedFee:String) {
        // Switch selected fee rate.
        
        let availableBalance:Int = self.coreVC!.bittrWallet.satoshisOnchain
        
        switch tappedFee {
        case "fast":
            let feeInSats = Int(self.stringToNumber(self.satsFast.text!.replacingOccurrences(of: " sats", with: "")))
            self.selectedFeeInSats = feeInSats
            
            if self.checkFeeAvailability(tappedFee:tappedFee, feeInSats: feeInSats, actualAmount: self.onchainAmountInSatoshis, availableBalance: availableBalance) {
                self.fastView.backgroundColor = Colors.getColor("whiteorblue3")
                self.mediumView.backgroundColor = Colors.getColor("white0.7orblue2")
                self.slowView.backgroundColor = Colors.getColor("white0.7orblue2")
                self.selectedFee = "high"
                
                if self.stringToNumber(self.satsFast.text!.replacingOccurrences(of: " sats", with: "")) / CGFloat(self.onchainAmountInSatoshis) > 0.1 {
                    
                    self.showAlert(presentingController: self, title: Language.getWord(withID: "highfeerate"), message: Language.getWord(withID: "highfeerate2"), buttons: [Language.getWord(withID: "okay")], actions: nil)
                }
            }
        case "medium":
            let feeInSats = Int(self.stringToNumber(self.satsMedium.text!.replacingOccurrences(of: " sats", with: "")))
            self.selectedFeeInSats = feeInSats
            
            if self.checkFeeAvailability(tappedFee:tappedFee, feeInSats: feeInSats, actualAmount: self.onchainAmountInSatoshis, availableBalance: availableBalance) {
                self.fastView.backgroundColor = Colors.getColor("white0.7orblue2")
                self.mediumView.backgroundColor = Colors.getColor("whiteorblue3")
                self.slowView.backgroundColor = Colors.getColor("white0.7orblue2")
                self.selectedFee = "medium"
                
                if self.stringToNumber(self.satsMedium.text!.replacingOccurrences(of: " sats", with: "")) / CGFloat(self.onchainAmountInSatoshis) > 0.1 {
                    
                    self.showAlert(presentingController: self, title: Language.getWord(withID: "highfeerate"), message: Language.getWord(withID: "highfeerate2"), buttons: [Language.getWord(withID: "okay")], actions: nil)
                }
            }
        case "slow":
            self.fastView.backgroundColor = Colors.getColor("white0.7orblue2")
            self.mediumView.backgroundColor = Colors.getColor("white0.7orblue2")
            self.slowView.backgroundColor = Colors.getColor("whiteorblue3")
            self.selectedFee = "low"
            
            if self.stringToNumber(self.satsSlow.text!.replacingOccurrences(of: " sats", with: "")) / CGFloat(self.onchainAmountInSatoshis) > 0.1 {
                
                self.showAlert(presentingController: self, title: Language.getWord(withID: "highfeerate"), message: Language.getWord(withID: "highfeerate2"), buttons: [Language.getWord(withID: "okay")], actions: nil)
            }
        default:
            self.fastView.backgroundColor = Colors.getColor("white0.7orblue2")
            self.mediumView.backgroundColor = Colors.getColor("whiteorblue3")
            self.slowView.backgroundColor = Colors.getColor("white0.7orblue2")
            self.selectedFee = "medium"
            
            if self.stringToNumber(self.satsMedium.text!.replacingOccurrences(of: " sats", with: "")) / CGFloat(self.onchainAmountInSatoshis) > 0.1 {
                
                self.showAlert(presentingController: self, title: Language.getWord(withID: "highfeerate"), message: Language.getWord(withID: "highfeerate2"), buttons: [Language.getWord(withID: "okay")], actions: nil)
            }
        }
    }
    
    
    func checkFeeAvailability(tappedFee:String, feeInSats:Int, actualAmount:Int, availableBalance:Int) -> Bool {
        
        if feeInSats + actualAmount > availableBalance {
            self.showAlert(presentingController: self, title: Language.getWord(withID: "balance2"), message: "\(Language.getWord(withID: "youravailablebalance")) (\(availableBalance) sats) \(Language.getWord(withID: "isinsufficient")).", buttons: [Language.getWord(withID: "updateamount"), Language.getWord(withID: "close")], actions: [#selector(self.handleAmountChange), nil])
            return false
        } else {
            return true
        }
    }
    
    @objc func handleAmountChange() {
        self.hideAlert()
        
        self.amountTextField.text = "\(CGFloat(self.coreVC!.bittrWallet.satoshisOnchain-self.selectedFeeInSats)/100000000)".replacingOccurrences(of: "00000000001", with: "").replacingOccurrences(of: "99999999999", with: "").replacingOccurrences(of: "0000000001", with: "").replacingOccurrences(of: "9999999999", with: "")
        
        let bitcoinValue = self.getCorrectBitcoinValue(coreVC: self.coreVC!)
        self.confirmAmountLabel.text = "\(formatBitcoinAmount(self.onchainAmountInBTC)) BTC"
        self.confirmEuroLabel.text = "\(Int(self.onchainAmountInBTC*bitcoinValue.currentValue)) \(bitcoinValue.chosenCurrency)"
        
        var thisSelectedFee = self.selectedFee
        if thisSelectedFee == "high" {
            thisSelectedFee = "fast"
        }
        self.switchFeeSelection(tappedFee:thisSelectedFee)
    }
    
    func confirmSendOnchain() {
        // Send onchain transaction.
        // Check whether selected fee is appropriate.
        
        if self.slowTimeLabel.text == "Slow" && self.selectedFee == "low" {
            // Selected fee is very low.
            self.showAlert(presentingController: self, title: Language.getWord(withID: "lowfee"), message: Language.getWord(withID: "lowfee2"), buttons: [Language.getWord(withID: "changefee"), Language.getWord(withID: "continue")], actions: [nil, #selector(self.proceedWithOnchainConfirmation)])
        } else {
            self.proceedWithOnchainConfirmation()
        }
    }
    
    @objc func proceedWithOnchainConfirmation() {
        self.hideAlert()
        
        var feeSatoshis = (self.satsMedium.text ?? "no").replacingOccurrences(of: " sats", with: "")
        if self.selectedFee == "low" {
            feeSatoshis = (self.satsSlow.text ?? "no").replacingOccurrences(of: " sats", with: "")
        } else if self.selectedFee == "high" {
            feeSatoshis = (self.satsFast.text ?? "no").replacingOccurrences(of: " sats", with: "")
        }
        
        self.showAlert(presentingController: self, title: Language.getWord(withID: "sendtransaction"), message: "\(Language.getWord(withID: "sendconfirmation")) \(self.onchainAmountInBTC) btc, \(Language.getWord(withID: "sendconfirmation2")) \(feeSatoshis) satoshis, \(Language.getWord(withID: "to")) \(self.confirmAddressLabel.text ?? Language.getWord(withID: "thisaddress"))?", buttons: [Language.getWord(withID: "cancel"), Language.getWord(withID: "confirm")], actions: [nil, #selector(self.performOnchainTransaction)])
    }
    
    @objc func performOnchainTransaction() {
        self.hideAlert()
        
        self.sendLabel.alpha = 0
        self.sendSpinner.startAnimating()
        
        if let actualWallet = LightningNodeService.shared.getWallet()/*, let actualBlockchain = LightningNodeService.shared.getBlockchain()*/ {
            
            let actualAddress:String = self.confirmAddressLabel.text!
            
            Task {
                do {
                    var selectedVbyte:Float = self.feeMedium
                    if self.selectedFee == "low" {
                        selectedVbyte = self.feeLow
                    } else if self.selectedFee == "high" {
                        selectedVbyte = self.feeHigh
                    }
                    let tx = try self.getTx(address: actualAddress, amountSats: self.onchainAmountInSatoshis, wallet: actualWallet, selectedVbyte: selectedVbyte)
                    
                    if let client = LightningNodeService.shared.getClient() {
                        
                        let txid = try client.transactionBroadcast(tx: tx)
                        
                        print("Transaction ID: \(txid)")
                        
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            print("Successful transaction.")
                            self.sendLabel.alpha = 1
                            self.sendSpinner.stopAnimating()
                            self.newTxId = txid
                            
                            self.showAlert(presentingController: self, title: Language.getWord(withID: "success"), message: Language.getWord(withID: "transactionsuccess"), buttons: [Language.getWord(withID: "okay")], actions: [#selector(self.addNewTxToTable)])
                        }
                    }
                } catch {
                    print("Transaction error: \(error.localizedDescription)")
                    self.showAlert(presentingController: self, title: Language.getWord(withID: "error"), message: "\(Language.getWord(withID: "transactionerror")): \(error.localizedDescription).", buttons: [Language.getWord(withID: "okay")], actions: nil)
                }
            }
        } else {
            print("Wallet or Blockchain instance not available.")
            self.showAlert(presentingController: self, title: Language.getWord(withID: "error"), message: Language.getWord(withID: "transactionerror2"), buttons: [Language.getWord(withID: "okay")], actions: nil)
        }
    }
    
    @objc func addNewTxToTable() {
        self.hideAlert()
        
        LightningNodeService.shared.lightSync() { success in
            if success, self.coreVC?.bittrWallet.transactionsOnchain != nil {
                for eachTransaction in self.coreVC!.bittrWallet.transactionsOnchain! {
                    if eachTransaction.transaction.computeTxid() == self.newTxId {
                        self.completedTransaction = self.createTransaction(transactionDetails: eachTransaction, paymentDetails: nil, bittrTransaction: nil, swapTransaction: nil, coreVC: self.coreVC!, bittrTransactions: nil)
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
    
    func getMaximumSendableSats() -> Double? {
        
        if let actualWallet = LightningNodeService.shared.getWallet() {
            do {
                let actualAddress:String = actualWallet.peekAddress(keychain: .external, index: 0).address.description
                let bdkNetwork = EnvironmentConfig.bitcoinDevKitNetwork
                let address = try Address(address: actualAddress, network: bdkNetwork)
                let script = address.scriptPubkey()
                let actualAmount:Int = Int(actualWallet.balance().trustedSpendable.toSat())
                let txBuilder = TxBuilder().addRecipient(script: script, amount: BitcoinDevKit.Amount.fromSat(satoshi: UInt64(actualAmount)))
                let details = try txBuilder.finish(wallet: actualWallet)
                let _ = try actualWallet.sign(psbt: details, signOptions: nil)
                
                return nil
            } catch {
                if error.localizedDescription.contains("Insufficient funds") {
                    let satsReservation:Double = self.stringToNumber(String(error.localizedDescription.split(separator: " ")[7]))
                    let btcOnchain = CGFloat(self.coreVC!.bittrWallet.satoshisOnchain)*0.00000001
                    let requiredCorrection:Double = btcOnchain - satsReservation
                    let spendableBtcAmount = btcOnchain + requiredCorrection
                    if spendableBtcAmount < 0 {
                        return 0
                    } else {
                        return spendableBtcAmount
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
        if let homeVC = self.homeVC {
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

extension UIViewController {
    
    func stringToNumber(_ thisString:String?) -> CGFloat {
        
        let formatter = NumberFormatter()
        formatter.decimalSeparator = Locale.current.decimalSeparator!
        
        if formatter.number(from: (thisString ?? "0.0").fixDecimals()) == nil {
            return 0
        } else {
            return CGFloat(truncating: formatter.number(from: (thisString ?? "0.0").fixDecimals())!)
        }
    }
    
    func getSize(address:String, amountSats:Int, wallet:BitcoinDevKit.Wallet) throws -> UInt64 {
        
        let tx = try self.getTx(address: address, amountSats: amountSats, wallet: wallet, selectedVbyte: nil)
        let size = tx.vsize()
        
        return size
    }
    
    func getTx(address:String, amountSats:Int, wallet:BitcoinDevKit.Wallet, selectedVbyte:Float?) throws -> BitcoinDevKit.Transaction {
        
        let network = EnvironmentConfig.bitcoinDevKitNetwork
        let address = try Address(address: address, network: network)
        let script = address.scriptPubkey()
        var txBuilder = TxBuilder().addRecipient(script: script, amount: BitcoinDevKit.Amount.fromSat(satoshi: UInt64(amountSats)))
        if selectedVbyte != nil {
            txBuilder = txBuilder.feeRate(feeRate: try FeeRate.fromSatPerVb(satVb: UInt64(selectedVbyte!)))
        }
        let details = try txBuilder.finish(wallet: wallet)
        let _ = try wallet.sign(psbt: details, signOptions: nil)
        let tx = try details.extractTx()
        
        return tx
    }
}
