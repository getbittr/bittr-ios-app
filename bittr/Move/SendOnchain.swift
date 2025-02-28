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
                self.showAlert(title: Language.getWord(withID: "oops"), message: Language.getWord(withID: "spendablebalance"), buttons: [Language.getWord(withID: "okay")], actions: nil)
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
                            
                            var address = try Address(address: actualAddress, network: .bitcoin)
                            if UserDefaults.standard.value(forKey: "envkey") as? Int == 0 {
                                address = try Address(address: actualAddress, network: .testnet)
                            }
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
                                    self.showAlert(title: Language.getWord(withID: "oops"), message: "\(Language.getWord(withID: "cannotproceed")). \(condensedMessage).", buttons: [Language.getWord(withID: "okay")], actions: nil)
                                } else {
                                    self.showAlert(title: Language.getWord(withID: "oops"), message: "\(Language.getWord(withID: "cannotproceed")). Error: \(error).", buttons: [Language.getWord(withID: "okay")], actions: nil)
                                }
                                
                                SentrySDK.capture(error: error)
                            }
                        } catch {
                            print("Error: \(error.localizedDescription)")
                            DispatchQueue.main.async {
                                self.nextLabel.alpha = 1
                                self.nextSpinner.stopAnimating()
                                
                                self.showAlert(title: Language.getWord(withID: "oops"), message: "\(Language.getWord(withID: "cannotproceed")). Error: \(error.localizedDescription).", buttons: [Language.getWord(withID: "okay")], actions: nil)
                                
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
                    
                    self.showAlert(title: Language.getWord(withID: "highfeerate"), message: Language.getWord(withID: "highfeerate2"), buttons: [Language.getWord(withID: "okay")], actions: nil)
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
                    
                    self.showAlert(title: Language.getWord(withID: "highfeerate"), message: Language.getWord(withID: "highfeerate2"), buttons: [Language.getWord(withID: "okay")], actions: nil)
                }
            }
        case "slow":
            self.fastView.backgroundColor = Colors.getColor("white0.7orblue2")
            self.mediumView.backgroundColor = Colors.getColor("white0.7orblue2")
            self.slowView.backgroundColor = Colors.getColor("whiteorblue3")
            self.selectedFee = "low"
            
            if self.stringToNumber(self.satsSlow.text!.replacingOccurrences(of: " sats", with: "")) / CGFloat(self.onchainAmountInSatoshis) > 0.1 {
                
                self.showAlert(title: Language.getWord(withID: "highfeerate"), message: Language.getWord(withID: "highfeerate2"), buttons: [Language.getWord(withID: "okay")], actions: nil)
            }
        default:
            self.fastView.backgroundColor = Colors.getColor("white0.7orblue2")
            self.mediumView.backgroundColor = Colors.getColor("whiteorblue3")
            self.slowView.backgroundColor = Colors.getColor("white0.7orblue2")
            self.selectedFee = "medium"
            
            if self.stringToNumber(self.satsMedium.text!.replacingOccurrences(of: " sats", with: "")) / CGFloat(self.onchainAmountInSatoshis) > 0.1 {
                
                self.showAlert(title: Language.getWord(withID: "highfeerate"), message: Language.getWord(withID: "highfeerate2"), buttons: [Language.getWord(withID: "okay")], actions: nil)
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
                        var address = try Address(address: actualAddress, network: .bitcoin)
                        if UserDefaults.standard.value(forKey: "envkey") as? Int == 0 {
                            address = try Address(address: actualAddress, network: .testnet)
                        }
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
                            self.newTxId = txid
                            
                            self.showAlert(title: Language.getWord(withID: "success"), message: Language.getWord(withID: "transactionsuccess"), buttons: [Language.getWord(withID: "okay")], actions: [#selector(self.addNewTxToTable)])
                        }
                    } catch {
                        print("Transaction error: \(error.localizedDescription)")
                        self.showAlert(title: Language.getWord(withID: "error"), message: "\(Language.getWord(withID: "transactionerror")): \(error.localizedDescription).", buttons: [Language.getWord(withID: "okay")], actions: nil)
                    }
                }
            } else {
                print("Wallet or Blockchain instance not available.")
                self.showAlert(title: Language.getWord(withID: "error"), message: Language.getWord(withID: "transactionerror2"), buttons: [Language.getWord(withID: "okay")], actions: nil)
            }
        }))
        self.present(alert, animated: true)
    }
    
    @objc func addNewTxToTable() {
        self.hideAlert()
        
        let newTransaction = Transaction()
        newTransaction.id = "\(self.newTxId)"
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
    }
    
    func getMaximumSendableSats() -> Double? {
        
        if let actualWallet = LightningNodeService.shared.getWallet() {
            do {
                let actualAddress:String = try actualWallet.getAddress(addressIndex: AddressIndex.peek(index: 0)).address.asString()
                let actualAmount:Int = Int(try actualWallet.getBalance().spendable)
                var address = try Address(address: actualAddress, network: .bitcoin)
                if UserDefaults.standard.value(forKey: "envkey") as? Int == 0 {
                    address = try Address(address: actualAddress, network: .testnet)
                }
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
    
    func showAlert(title:String, message:String, buttons:[String], actions:[Selector]?) {
        /*DispatchQueue.main.async {
            let alert = UIAlertController(title: alertTitle, message: alertMessage, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: alertButton, style: .cancel, handler: nil))
            self.present(alert, animated: true)
        }*/
        
        DispatchQueue.main.async {
            
            // Background
            let darkBackground = UIView()
            darkBackground.translatesAutoresizingMaskIntoConstraints = false
            darkBackground.backgroundColor = UIColor(red: 0, green: 0, blue: 0, alpha: 0.5)
            darkBackground.accessibilityIdentifier = "alertview"
            self.view.addSubview(darkBackground)
            let darkBackgroundTop = NSLayoutConstraint(item: darkBackground, attribute: .top, relatedBy: .equal, toItem: self.view, attribute: .top, multiplier: 1, constant: 0)
            let darkBackgroundBottom = NSLayoutConstraint(item: darkBackground, attribute: .bottom, relatedBy: .equal, toItem: self.view, attribute: .bottom, multiplier: 1, constant: 0)
            let darkBackgroundLeft = NSLayoutConstraint(item: darkBackground, attribute: .leading, relatedBy: .equal, toItem: self.view, attribute: .leading, multiplier: 1, constant: 0)
            let darkBackgroundRight = NSLayoutConstraint(item: darkBackground, attribute: .trailing, relatedBy: .equal, toItem: self.view, attribute: .trailing, multiplier: 1, constant: 0)
            self.view.addConstraints([darkBackgroundTop, darkBackgroundLeft, darkBackgroundRight, darkBackgroundBottom])
            
            // Card
            let yellowCard = UIView()
            yellowCard.translatesAutoresizingMaskIntoConstraints = false
            yellowCard.backgroundColor = Colors.getColor("yelloworblue2")
            yellowCard.layer.cornerRadius = 13
            yellowCard.layer.shadowColor = UIColor.black.cgColor
            yellowCard.layer.shadowOffset = CGSize(width: 0, height: 7)
            yellowCard.layer.shadowRadius = 10.0
            yellowCard.layer.shadowOpacity = 0.1
            yellowCard.clipsToBounds = false
            darkBackground.addSubview(yellowCard)
            let yellowCardCenterY = NSLayoutConstraint(item: yellowCard, attribute: .centerY, relatedBy: .equal, toItem: darkBackground, attribute: .centerY, multiplier: 1, constant: 0)
            let yellowCardLeft = NSLayoutConstraint(item: yellowCard, attribute: .leading, relatedBy: .equal, toItem: darkBackground, attribute: .leading, multiplier: 1, constant: 30)
            let yellowCardRight = NSLayoutConstraint(item: yellowCard, attribute: .trailing, relatedBy: .equal, toItem: darkBackground, attribute: .trailing, multiplier: 1, constant: -30)
            let yellowCardHeight = NSLayoutConstraint(item: yellowCard, attribute: .height, relatedBy: .lessThanOrEqual, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: self.view.bounds.height)
            darkBackground.addConstraints([yellowCardCenterY, yellowCardLeft, yellowCardRight])
            yellowCard.addConstraint(yellowCardHeight)
            
            // Icon
            let alertIcon = UIImageView()
            alertIcon.translatesAutoresizingMaskIntoConstraints = false
            alertIcon.contentMode = .scaleAspectFit
            if CacheManager.darkModeIsOn() {
                alertIcon.image = UIImage(named: "iconmailboxyellow")
            } else {
                alertIcon.image = UIImage(named: "iconmailboxwhite")
            }
            yellowCard.addSubview(alertIcon)
            let alertIconTop = NSLayoutConstraint(item: alertIcon, attribute: .top, relatedBy: .equal, toItem: yellowCard, attribute: .top, multiplier: 1, constant: 19)
            let alertIconLeft = NSLayoutConstraint(item: alertIcon, attribute: .leading, relatedBy: .equal, toItem: yellowCard, attribute: .leading, multiplier: 1, constant: 20)
            let alertIconHeight = NSLayoutConstraint(item: alertIcon, attribute: .height, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 21)
            let alertIconWidth = NSLayoutConstraint(item: alertIcon, attribute: .width, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 21)
            yellowCard.addConstraints([alertIconTop, alertIconLeft])
            alertIcon.addConstraints([alertIconHeight, alertIconWidth])
            
            // Header
            let headerLabel = UILabel()
            headerLabel.translatesAutoresizingMaskIntoConstraints = false
            headerLabel.numberOfLines = 1
            headerLabel.font = UIFont(name: "Gilroy-Bold", size: 18)
            headerLabel.text = Language.getWord(withID: "message")
            headerLabel.textColor = Colors.getColor("whiteoryellow")
            yellowCard.addSubview(headerLabel)
            let headerLabelCenterY = NSLayoutConstraint(item: headerLabel, attribute: .centerY, relatedBy: .equal, toItem: alertIcon, attribute: .centerY, multiplier: 1, constant: 0)
            let headerLabelLeft = NSLayoutConstraint(item: headerLabel, attribute: .leading, relatedBy: .equal, toItem: alertIcon, attribute: .trailing, multiplier: 1, constant: 10)
            let headerLabelHeight = NSLayoutConstraint(item: headerLabel, attribute: .height, relatedBy: .greaterThanOrEqual, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 0)
            let headerLabelWidth = NSLayoutConstraint(item: headerLabel, attribute: .width, relatedBy: .greaterThanOrEqual, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 0)
            yellowCard.addConstraints([headerLabelCenterY, headerLabelLeft])
            headerLabel.addConstraints([headerLabelHeight, headerLabelWidth])
            
            // Close image
            let closeIcon = UIImageView()
            closeIcon.translatesAutoresizingMaskIntoConstraints = false
            closeIcon.contentMode = .scaleAspectFit
            if CacheManager.darkModeIsOn() {
                closeIcon.image = UIImage(named: "iconcloseyellow")
            } else {
                closeIcon.image = UIImage(named: "iconclosewhite")
            }
            yellowCard.addSubview(closeIcon)
            let closeIconCenterY = NSLayoutConstraint(item: closeIcon, attribute: .centerY, relatedBy: .equal, toItem: alertIcon, attribute: .centerY, multiplier: 1, constant: 0)
            let closeIconRight = NSLayoutConstraint(item: closeIcon, attribute: .trailing, relatedBy: .equal, toItem: yellowCard, attribute: .trailing, multiplier: 1, constant: -20)
            let closeIconHeight = NSLayoutConstraint(item: closeIcon, attribute: .height, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 16)
            let closeIconWidth = NSLayoutConstraint(item: closeIcon, attribute: .width, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 16)
            yellowCard.addConstraints([closeIconCenterY, closeIconRight])
            closeIcon.addConstraints([closeIconHeight, closeIconWidth])
            
            // Close button
            let closeButton = UIButton()
            closeButton.translatesAutoresizingMaskIntoConstraints = false
            closeButton.setTitle("", for: .normal)
            closeButton.backgroundColor = .clear
            closeButton.addTarget(self, action: #selector(self.hideAlert), for: .touchUpInside)
            if actions == nil {
                closeIcon.alpha = 1
                closeButton.alpha = 1
            } else {
                // Hide close icon for alerts with a specific function.
                closeIcon.alpha = 0
                closeButton.alpha = 0
            }
            yellowCard.addSubview(closeButton)
            let closeButtonCenterX = NSLayoutConstraint(item: closeButton, attribute: .centerX, relatedBy: .equal, toItem: closeIcon, attribute: .centerX, multiplier: 1, constant: 0)
            let closeButtonCenterY = NSLayoutConstraint(item: closeButton, attribute: .centerY, relatedBy: .equal, toItem: closeIcon, attribute: .centerY, multiplier: 1, constant: 0)
            let closeButtonHeight = NSLayoutConstraint(item: closeButton, attribute: .height, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 40)
            let closeButtonWidth = NSLayoutConstraint(item: closeButton, attribute: .width, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 40)
            yellowCard.addConstraints([closeButtonCenterX, closeButtonCenterY])
            closeButton.addConstraints([closeButtonWidth, closeButtonHeight])
            
            // Message title
            let titleLabel = UILabel()
            titleLabel.translatesAutoresizingMaskIntoConstraints = false
            titleLabel.numberOfLines = 1
            titleLabel.font = UIFont(name: "Gilroy-Bold", size: 16)
            titleLabel.text = title
            titleLabel.textColor = Colors.getColor("blackorwhite")
            titleLabel.textAlignment = .center
            yellowCard.addSubview(titleLabel)
            let titleLabelTop = NSLayoutConstraint(item: titleLabel, attribute: .top, relatedBy: .equal, toItem: alertIcon, attribute: .bottom, multiplier: 1, constant: 25)
            let titleLabelCenterX = NSLayoutConstraint(item: titleLabel, attribute: .centerX, relatedBy: .equal, toItem: yellowCard, attribute: .centerX, multiplier: 1, constant: 0)
            let titleLabelHeight = NSLayoutConstraint(item: titleLabel, attribute: .height, relatedBy: .greaterThanOrEqual, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 0)
            let titleLabelWidth = NSLayoutConstraint(item: titleLabel, attribute: .width, relatedBy: .greaterThanOrEqual, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 0)
            yellowCard.addConstraints([titleLabelTop, titleLabelCenterX])
            titleLabel.addConstraints([titleLabelHeight, titleLabelWidth])
            
            // Message
            let messageLabel = UILabel()
            messageLabel.translatesAutoresizingMaskIntoConstraints = false
            messageLabel.numberOfLines = 0
            messageLabel.font = UIFont(name: "Gilroy-Regular", size: 16)
            messageLabel.text = message
            messageLabel.textColor = Colors.getColor("blackorwhite")
            messageLabel.textAlignment = .center
            yellowCard.addSubview(messageLabel)
            let messageLabelTop = NSLayoutConstraint(item: messageLabel, attribute: .top, relatedBy: .equal, toItem: titleLabel, attribute: .bottom, multiplier: 1, constant: 8)
            let messageLabelLeft = NSLayoutConstraint(item: messageLabel, attribute: .leading, relatedBy: .equal, toItem: yellowCard, attribute: .leading, multiplier: 1, constant: 40)
            let messageLabelRight = NSLayoutConstraint(item: messageLabel, attribute: .trailing, relatedBy: .equal, toItem: yellowCard, attribute: .trailing, multiplier: 1, constant: -40)
            let messageLabelHeight = NSLayoutConstraint(item: messageLabel, attribute: .height, relatedBy: .greaterThanOrEqual, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 0)
            yellowCard.addConstraints([messageLabelLeft, messageLabelRight, messageLabelTop])
            messageLabel.addConstraints([messageLabelHeight])
            
            // Buttons stack
            let buttonsStack = UIView()
            buttonsStack.translatesAutoresizingMaskIntoConstraints = false
            buttonsStack.clipsToBounds = false
            buttonsStack.backgroundColor = .clear
            yellowCard.addSubview(buttonsStack)
            let buttonsStackHeight = NSLayoutConstraint(item: buttonsStack, attribute: .height, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 50)
            let buttonsStackLeft = NSLayoutConstraint(item: buttonsStack, attribute: .leading, relatedBy: .equal, toItem: yellowCard, attribute: .leading, multiplier: 1, constant: 10)
            let buttonsStackRight = NSLayoutConstraint(item: buttonsStack, attribute: .trailing, relatedBy: .equal, toItem: yellowCard, attribute: .trailing, multiplier: 1, constant: -10)
            let buttonsStackBottom = NSLayoutConstraint(item: buttonsStack, attribute: .bottom, relatedBy: .equal, toItem: yellowCard, attribute: .bottom, multiplier: 1, constant: 0)
            let buttonsStackTop = NSLayoutConstraint(item: buttonsStack, attribute: .top, relatedBy: .equal, toItem: messageLabel, attribute: .bottom, multiplier: 1, constant: 35)
            yellowCard.addConstraints([buttonsStackLeft, buttonsStackRight, buttonsStackBottom, buttonsStackTop])
            buttonsStack.addConstraint(buttonsStackHeight)
            
            if buttons.count == 1 {
                
                // Close view
                let closeView = UIView()
                closeView.translatesAutoresizingMaskIntoConstraints = false
                closeView.backgroundColor = Colors.getColor("white0.7orblue1")
                closeView.layer.cornerRadius = 8
                closeView.layer.shadowColor = UIColor.black.cgColor
                closeView.layer.shadowOffset = CGSize(width: 0, height: 7)
                closeView.layer.shadowRadius = 10.0
                closeView.layer.shadowOpacity = 0.1
                closeView.clipsToBounds = false
                buttonsStack.addSubview(closeView)
                let closeViewTop = NSLayoutConstraint(item: closeView, attribute: .top, relatedBy: .equal, toItem: buttonsStack, attribute: .top, multiplier: 1, constant: 0)
                let closeViewBottom = NSLayoutConstraint(item: closeView, attribute: .bottom, relatedBy: .equal, toItem: buttonsStack, attribute: .bottom, multiplier: 1, constant: -10)
                let closeViewLeft = NSLayoutConstraint(item: closeView, attribute: .leading, relatedBy: .equal, toItem: buttonsStack, attribute: .leading, multiplier: 1, constant: 0)
                let closeViewRight = NSLayoutConstraint(item: closeView, attribute: .trailing, relatedBy: .equal, toItem: buttonsStack, attribute: .trailing, multiplier: 1, constant: 0)
                let closeViewHeight = NSLayoutConstraint(item: closeView, attribute: .height, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 40)
                buttonsStack.addConstraints([closeViewTop, closeViewBottom, closeViewLeft, closeViewRight])
                closeView.addConstraint(closeViewHeight)
                
                // Button label
                let buttonLabel = UILabel()
                buttonLabel.translatesAutoresizingMaskIntoConstraints = false
                buttonLabel.numberOfLines = 1
                buttonLabel.font = UIFont(name: "Gilroy-Bold", size: 16)
                buttonLabel.text = buttons[0]
                buttonLabel.textColor = Colors.getColor("blackorwhite")
                buttonLabel.textAlignment = .center
                closeView.addSubview(buttonLabel)
                let buttonLabelCenterX = NSLayoutConstraint(item: buttonLabel, attribute: .centerX, relatedBy: .equal, toItem: closeView, attribute: .centerX, multiplier: 1, constant: 0)
                let buttonLabelCenterY = NSLayoutConstraint(item: buttonLabel, attribute: .centerY, relatedBy: .equal, toItem: closeView, attribute: .centerY, multiplier: 1, constant: 1)
                let buttonLabelHeight = NSLayoutConstraint(item: buttonLabel, attribute: .height, relatedBy: .greaterThanOrEqual, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 0)
                let buttonLabelWidth = NSLayoutConstraint(item: buttonLabel, attribute: .width, relatedBy: .greaterThanOrEqual, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 0)
                closeView.addConstraints([buttonLabelCenterX, buttonLabelCenterY])
                buttonLabel.addConstraints([buttonLabelHeight, buttonLabelWidth])
                
                // Main button
                let mainButton = UIButton()
                mainButton.translatesAutoresizingMaskIntoConstraints = false
                mainButton.setTitle("", for: .normal)
                mainButton.backgroundColor = .clear
                if actions == nil {
                    mainButton.addTarget(self, action: #selector(self.hideAlert), for: .touchUpInside)
                } else {
                    mainButton.addTarget(self, action: actions![0], for: .touchUpInside)
                }
                buttonsStack.addSubview(mainButton)
                let mainButtonBottom = NSLayoutConstraint(item: mainButton, attribute: .bottom, relatedBy: .equal, toItem: buttonsStack, attribute: .bottom, multiplier: 1, constant: 0)
                let mainButtonLeft = NSLayoutConstraint(item: mainButton, attribute: .leading, relatedBy: .equal, toItem: buttonsStack, attribute: .leading, multiplier: 1, constant: 0)
                let mainButtonRight = NSLayoutConstraint(item: mainButton, attribute: .trailing, relatedBy: .equal, toItem: buttonsStack, attribute: .trailing, multiplier: 1, constant: 0)
                let mainButtonTop = NSLayoutConstraint(item: mainButton, attribute: .top, relatedBy: .equal, toItem: buttonsStack, attribute: .top, multiplier: 1, constant: 0)
                yellowCard.addConstraints([mainButtonTop, mainButtonLeft, mainButtonRight, mainButtonBottom])
            }
            
            self.view.layoutIfNeeded()
        }
    }
    
    @objc func hideAlert() {
        for eachView in self.view.subviews {
            if eachView.accessibilityIdentifier == "alertview" {
                eachView.removeFromSuperview()
            }
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
