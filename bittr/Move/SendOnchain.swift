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
                    self.confirmLightningTransaction(lnurlinvoice: invoiceText!, sendVC: self, receiveVC: nil)
                    return
                }
            }
            
            // Transfer to bitcoin.
            var divideBy:CGFloat = 1
            if self.selectedCurrency == "satoshis" {
                divideBy = 100000000
            } else if self.selectedCurrency == "currency" {
                divideBy = self.eurValue
                if UserDefaults.standard.value(forKey: "currency") as? String == "CHF" {
                    divideBy = self.chfValue
                }
            }
            
            self.onchainAmountInSatoshis = Int(((self.stringToNumber(self.amountTextField.text)/divideBy) * 100000000).rounded())
            self.onchainAmountInBTC = CGFloat(self.onchainAmountInSatoshis)/100000000
            
            if invoiceText == nil || invoiceText?.trimmingCharacters(in: .whitespaces) == "" || self.amountTextField.text == nil || self.amountTextField.text?.trimmingCharacters(in: .whitespacesAndNewlines) == "" || self.onchainAmountInSatoshis == 0  {
                
                // Fields are left empty or the amount if set to zero.
                
            } else if self.onchainAmountInBTC > self.btcAmount {
                // Insufficient funds available.
                self.showAlert(Language.getWord(withID: "oops"), Language.getWord(withID: "spendablebalance"), Language.getWord(withID: "okay"))
            } else {
            
                self.nextLabel.alpha = 0
                self.nextSpinner.startAnimating()
                
                var currencySymbol = "€"
                var conversionRate:CGFloat = 0
                var eurAmount = CacheManager.getCachedData(key: "eurvalue") as? CGFloat
                var chfAmount = CacheManager.getCachedData(key: "chfvalue") as? CGFloat
                conversionRate = eurAmount ?? 0.0
                if UserDefaults.standard.value(forKey: "currency") as? String == "CHF" {
                    currencySymbol = "CHF"
                    conversionRate = chfAmount ?? 0.0
                }
                
                self.confirmAddressLabel.text = invoiceText
                self.confirmAmountLabel.text = "\(self.onchainAmountInBTC) btc"
                self.confirmEuroLabel.text = "\(Int(self.onchainAmountInBTC*conversionRate)) \(currencySymbol)"
                
                if let actualBlockchain = LightningNodeService.shared.getBlockchain(), let actualWallet = LightningNodeService.shared.getWallet() {
                    
                    let actualAddress:String = invoiceText!
                    
                    Task {
                        do {
                            let high = try actualBlockchain.estimateFee(target: 1)
                            let medium = try actualBlockchain.estimateFee(target: 3)
                            let low = try actualBlockchain.estimateFee(target: 6)
                            
                            print("High: \(high.asSatPerVb()), Medium: \(medium.asSatPerVb()), Low: \(low.asSatPerVb())")
                            
                            self.feeLow = Float(Int(low.asSatPerVb()*10))/10
                            self.feeMedium = Float(Int(medium.asSatPerVb()*10))/10
                            self.feeHigh = Float(Int(high.asSatPerVb()*10))/10
                            
                            print("Adjusted - High: \(self.feeHigh), Medium: \(self.feeMedium), Low: \(self.feeLow)")
                            
                            var address = try Address(address: actualAddress, network: .signet)
                            let script = address.scriptPubkey()
                            let txBuilder = TxBuilder().addRecipient(script: script, amount: UInt64(self.onchainAmountInSatoshis))
                            let details = try txBuilder.finish(wallet: actualWallet)
                            let _ = try actualWallet.sign(psbt: details.psbt, signOptions: nil)
                            let tx = details.psbt.extractTx()
                            let size = tx.vsize()

                            print("Size: \(String(describing: size))")
                            print("High: \(self.feeHigh*Float(size)), Medium: \(self.feeMedium*Float(size)), Low: \(self.feeLow*Float(size))")
                            
                            let lowestSats:Float = self.feeLow*Float(size)
                            let availableSatsForFee:Float = Float((self.btcAmount*100000000) - Double(self.onchainAmountInSatoshis))
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
                            var fastText = "\(CGFloat(Int(((fast1/100000000)*conversionRate)*100))/100)"
                            if fastText.count == 3 {
                                fastText = fastText + "0"
                            }
                            let medium1 = CGFloat(self.feeMedium*Float(size))
                            var mediumText = "\(CGFloat(Int(((medium1/100000000)*conversionRate)*100))/100)"
                            if mediumText.count == 3 {
                                mediumText = mediumText + "0"
                            }
                            let slow1 = CGFloat(self.feeLow*Float(size))
                            var slowText = "\(CGFloat(Int(((slow1/100000000)*conversionRate)*100))/100)"
                            if slowText.count == 3 {
                                slowText = slowText + "0"
                            }
                            
                            self.eurosFast.text = fastText + " " + currencySymbol
                            self.eurosMedium.text = mediumText + " " + currencySymbol
                            self.eurosSlow.text = slowText + " " + currencySymbol
                            
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
                        } catch let error as BdkError {
                            
                            print("BDK error: \(error)")
                            DispatchQueue.main.async {
                                
                                self.nextLabel.alpha = 1
                                self.nextSpinner.stopAnimating()
                                
                                if "\(error)".contains("InsufficientFunds") {
                                    let condensedMessage = "\(error)".replacingOccurrences(of: "InsufficientFunds(message: \"", with: "").replacingOccurrences(of: "\")", with: "")
                                    self.showAlert(Language.getWord(withID: "oops"), "\(Language.getWord(withID: "cannotproceed")). \(condensedMessage).", Language.getWord(withID: "okay"))
                                } else {
                                    self.showAlert(Language.getWord(withID: "oops"), "\(Language.getWord(withID: "cannotproceed")). Error: \(error).", Language.getWord(withID: "okay"))
                                }
                                
                                SentrySDK.capture(error: error)
                            }
                        } catch {
                            print("Error: \(error.localizedDescription)")
                            DispatchQueue.main.async {
                                self.nextLabel.alpha = 1
                                self.nextSpinner.stopAnimating()
                                
                                self.showAlert(Language.getWord(withID: "oops"), "\(Language.getWord(withID: "cannotproceed")). Error: \(error.localizedDescription).", Language.getWord(withID: "okay"))
                                
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
        
        let availableBalance:Int = Int(self.btcAmount*100000000)
        
        switch tappedFee {
        case "fast":
            let feeInSats = Int(self.stringToNumber(self.satsFast.text!.replacingOccurrences(of: " sats", with: "")))
            
            if self.checkFeeAvailability(tappedFee:tappedFee, feeInSats: feeInSats, actualAmount: self.onchainAmountInSatoshis, availableBalance: availableBalance) {
                self.fastView.backgroundColor = Colors.getColor("whiteorblue3")
                self.mediumView.backgroundColor = Colors.getColor("white0.7orblue2")
                self.slowView.backgroundColor = Colors.getColor("white0.7orblue2")
                self.selectedFee = "high"
                
                if self.stringToNumber(self.satsFast.text!.replacingOccurrences(of: " sats", with: "")) / CGFloat(self.onchainAmountInSatoshis) > 0.1 {
                    
                    self.showAlert(Language.getWord(withID: "highfeerate"), Language.getWord(withID: "highfeerate2"), Language.getWord(withID: "okay"))
                }
            }
        case "medium":
            let feeInSats = Int(self.stringToNumber(self.satsMedium.text!.replacingOccurrences(of: " sats", with: "")))
            
            if self.checkFeeAvailability(tappedFee:tappedFee, feeInSats: feeInSats, actualAmount: self.onchainAmountInSatoshis, availableBalance: availableBalance) {
                self.fastView.backgroundColor = Colors.getColor("white0.7orblue2")
                self.mediumView.backgroundColor = Colors.getColor("whiteorblue3")
                self.slowView.backgroundColor = Colors.getColor("white0.7orblue2")
                self.selectedFee = "medium"
                
                if self.stringToNumber(self.satsMedium.text!.replacingOccurrences(of: " sats", with: "")) / CGFloat(self.onchainAmountInSatoshis) > 0.1 {
                    
                    self.showAlert(Language.getWord(withID: "highfeerate"), Language.getWord(withID: "highfeerate2"), Language.getWord(withID: "okay"))
                }
            }
        case "slow":
            self.fastView.backgroundColor = Colors.getColor("white0.7orblue2")
            self.mediumView.backgroundColor = Colors.getColor("white0.7orblue2")
            self.slowView.backgroundColor = Colors.getColor("whiteorblue3")
            self.selectedFee = "low"
            
            if self.stringToNumber(self.satsSlow.text!.replacingOccurrences(of: " sats", with: "")) / CGFloat(self.onchainAmountInSatoshis) > 0.1 {
                
                self.showAlert(Language.getWord(withID: "highfeerate"), Language.getWord(withID: "highfeerate2"), Language.getWord(withID: "okay"))
            }
        default:
            self.fastView.backgroundColor = Colors.getColor("white0.7orblue2")
            self.mediumView.backgroundColor = Colors.getColor("whiteorblue3")
            self.slowView.backgroundColor = Colors.getColor("white0.7orblue2")
            self.selectedFee = "medium"
            
            if self.stringToNumber(self.satsMedium.text!.replacingOccurrences(of: " sats", with: "")) / CGFloat(self.onchainAmountInSatoshis) > 0.1 {
                
                self.showAlert(Language.getWord(withID: "highfeerate"), Language.getWord(withID: "highfeerate2"), Language.getWord(withID: "okay"))
            }
        }
    }
    
    
    func checkFeeAvailability(tappedFee:String, feeInSats:Int, actualAmount:Int, availableBalance:Int) -> Bool {
        
        if feeInSats + actualAmount > availableBalance {
            let alert = UIAlertController(title: Language.getWord(withID: "balance2"), message: "\(Language.getWord(withID: "youravailablebalance")) (\(availableBalance) sats) \(Language.getWord(withID: "isinsufficient")).", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: Language.getWord(withID: "updateamount"), style: .default, handler: { _ in
                self.amountTextField.text = "\(CGFloat(availableBalance-feeInSats)/100000000)".replacingOccurrences(of: "00000000001", with: "").replacingOccurrences(of: "99999999999", with: "").replacingOccurrences(of: "0000000001", with: "").replacingOccurrences(of: "9999999999", with: "")
                
                var currencySymbol = "€"
                var conversionRate:CGFloat = 0
                var eurAmount = CacheManager.getCachedData(key: "eurvalue") as? CGFloat
                var chfAmount = CacheManager.getCachedData(key: "chfvalue") as? CGFloat
                conversionRate = eurAmount ?? 0.0
                if UserDefaults.standard.value(forKey: "currency") as? String == "CHF" {
                    currencySymbol = "CHF"
                    conversionRate = chfAmount ?? 0.0
                }
                self.confirmAmountLabel.text = "\(self.onchainAmountInBTC) btc"
                self.confirmEuroLabel.text = "\(Int(self.onchainAmountInBTC*conversionRate)) \(currencySymbol)"
                
                self.switchFeeSelection(tappedFee:tappedFee)
            }))
            alert.addAction(UIAlertAction(title: Language.getWord(withID: "close"), style: .cancel, handler: nil))
            self.present(alert, animated: true)
            return false
        } else {
            return true
        }
    }
    
    
    func confirmSendOnchain() {
        // Send onchain transaction.
        // Check whether selected fee is appropriate.
        
        if self.slowTimeLabel.text == "Slow" && self.selectedFee == "low" {
            // Selected fee is very low.
            let alert = UIAlertController(title: Language.getWord(withID: "lowfee"), message: Language.getWord(withID: "lowfee2"), preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: Language.getWord(withID: "changefee"), style: .cancel, handler: {_ in
                return
            }))
            alert.addAction(UIAlertAction(title: Language.getWord(withID: "continue"), style: .default, handler: {_ in
                self.proceedWithOnchainConfirmation()
            }))
            self.present(alert, animated: true)
        } else {
            self.proceedWithOnchainConfirmation()
        }
    }
    
    func proceedWithOnchainConfirmation() {
        
        var feeSatoshis = (self.satsMedium.text ?? "no").replacingOccurrences(of: " sats", with: "")
        if self.selectedFee == "low" {
            feeSatoshis = (self.satsSlow.text ?? "no").replacingOccurrences(of: " sats", with: "")
        } else if self.selectedFee == "high" {
            feeSatoshis = (self.satsFast.text ?? "no").replacingOccurrences(of: " sats", with: "")
        }
        
        let alert = UIAlertController(title: Language.getWord(withID: "sendtransaction"), message: "\(Language.getWord(withID: "sendconfirmation")) \(self.onchainAmountInBTC) btc, \(Language.getWord(withID: "sendconfirmation2")) \(feeSatoshis) satoshis, \(Language.getWord(withID: "to")) \(self.confirmAddressLabel.text ?? Language.getWord(withID: "thisaddress"))?", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: Language.getWord(withID: "cancel"), style: .cancel, handler: nil))
        alert.addAction(UIAlertAction(title: Language.getWord(withID: "confirm"), style: .default, handler: {_ in
            
            self.sendLabel.alpha = 0
            self.sendSpinner.startAnimating()
            
            if let actualWallet = LightningNodeService.shared.getWallet(), let actualBlockchain = LightningNodeService.shared.getBlockchain() {
                
                let actualAddress:String = self.confirmAddressLabel.text!
                
                Task {
                    do {
                        var address = try Address(address: actualAddress, network: .signet)
                        let script = address.scriptPubkey()
                        var selectedVbyte:Float = self.feeMedium
                        if self.selectedFee == "low" {
                            selectedVbyte = self.feeLow
                        } else if self.selectedFee == "high" {
                            selectedVbyte = self.feeHigh
                        }
                        let txBuilder = TxBuilder().addRecipient(script: script, amount: UInt64(self.onchainAmountInSatoshis)).feeRate(satPerVbyte: selectedVbyte)
                        let details = try txBuilder.finish(wallet: actualWallet)
                        let _ = try actualWallet.sign(psbt: details.psbt, signOptions: nil)
                        let tx = details.psbt.extractTx()
                        try actualBlockchain.broadcast(transaction: tx)
                        let txid = details.psbt.txid()
                        print("Transaction ID: \(txid)")
                        
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            print("Successful transaction.")
                            self.sendLabel.alpha = 1
                            self.sendSpinner.stopAnimating()
                            
                            let successAlert = UIAlertController(title: Language.getWord(withID: "success"), message: Language.getWord(withID: "transactionsuccess"), preferredStyle: .alert)
                            successAlert.addAction(UIAlertAction(title: Language.getWord(withID: "okay"), style: .default, handler: {_ in
                                
                                let newTransaction = Transaction()
                                newTransaction.id = "\(txid)"
                                newTransaction.confirmations = 0
                                newTransaction.timestamp = Int(Date().timeIntervalSince1970)
                                newTransaction.height = 0
                                newTransaction.received = 0
                                var satsLabel = self.satsMedium
                                if self.selectedFee == "low" {
                                    satsLabel = self.satsSlow
                                } else if self.selectedFee == "high" {
                                    satsLabel = self.satsFast
                                }
                                newTransaction.fee = Int(self.stringToNumber(satsLabel!.text!.replacingOccurrences(of: " sats", with: "")))
                                newTransaction.sent = self.onchainAmountInSatoshis + newTransaction.fee
                                newTransaction.isLightning = false
                                newTransaction.isBittr = false
                                
                                self.completedTransaction = newTransaction
                                
                                if let actualHomeVC = self.homeVC {
                                    actualHomeVC.setTransactions += [newTransaction]
                                    actualHomeVC.setTransactions.sort { transaction1, transaction2 in
                                        transaction1.timestamp > transaction2.timestamp
                                    }
                                    actualHomeVC.homeTableView.reloadData()
                                }
                                
                                self.performSegue(withIdentifier: "SendToTransaction", sender: self)
                                
                                self.resetFields()
                                
                                // Slide back to leftmost scroll view.
                                UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseInOut) {
                                    NSLayoutConstraint.deactivate([self.scrollViewTrailing])
                                    self.scrollViewTrailing = NSLayoutConstraint(item: self.scrollView, attribute: .trailing, relatedBy: .equal, toItem: self.view, attribute: .trailing, multiplier: 1, constant: 0)
                                    NSLayoutConstraint.activate([self.scrollViewTrailing])
                                    self.view.layoutIfNeeded()
                                }
                            }))
                            self.present(successAlert, animated: true)
                        }
                    } catch {
                        print("Transaction error: \(error.localizedDescription)")
                        self.showAlert(Language.getWord(withID: "error"), "\(Language.getWord(withID: "transactionerror")): \(error.localizedDescription).", Language.getWord(withID: "okay"))
                    }
                }
            } else {
                print("Wallet or Blockchain instance not available.")
                self.showAlert(Language.getWord(withID: "error"), Language.getWord(withID: "transactionerror2"), Language.getWord(withID: "okay"))
            }
        }))
        self.present(alert, animated: true)
    }
    
    func getMaximumSendableSats() -> Double? {
        
        if let actualWallet = LightningNodeService.shared.getWallet() {
            do {
                let actualAddress:String = try actualWallet.getAddress(addressIndex: AddressIndex.peek(index: 0)).address.asString()
                let actualAmount:Int = Int(try actualWallet.getBalance().spendable)
                var address = try Address(address: actualAddress, network: .signet)
                let script = address.scriptPubkey()
                let txBuilder = TxBuilder().addRecipient(script: script, amount: UInt64(actualAmount))
                let details = try txBuilder.finish(wallet: actualWallet)
                let _ = try actualWallet.sign(psbt: details.psbt, signOptions: nil)
                
                return nil
            } catch let error as BdkError {
                if "\(error)".contains("InsufficientFunds") {
                    let satsReservation:Double = self.stringToNumber(String("\(error)".split(separator: " ")[7])) * 0.00000001
                    let requiredCorrection:Double = self.btcAmount - satsReservation
                    let spendableBtcAmount = self.btcAmount + requiredCorrection
                    if spendableBtcAmount < 0 {
                        return 0
                    } else {
                        return spendableBtcAmount
                    }
                } else {
                    return nil
                }
            } catch {
                return nil
            }
        } else {
            return nil
        }
    }
}

extension UIViewController {
    
    func showAlert(_ alertTitle:String, _ alertMessage:String, _ alertButton:String) {
        DispatchQueue.main.async {
            let alert = UIAlertController(title: alertTitle, message: alertMessage, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: alertButton, style: .cancel, handler: nil))
            self.present(alert, animated: true)
        }
    }
    
    func stringToNumber(_ thisString:String?) -> CGFloat {
        
        let formatter = NumberFormatter()
        formatter.decimalSeparator = Locale.current.decimalSeparator!
        
        if formatter.number(from: (thisString ?? "0.0").fixDecimals()) == nil {
            return 0
        } else {
            return CGFloat(truncating: formatter.number(from: (thisString ?? "0.0").fixDecimals())!)
        }
    }
}
