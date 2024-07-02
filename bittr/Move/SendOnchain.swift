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
            if self.selectedInput != "keyboard" {
                invoiceText = self.invoiceLabel.text
            }
            
            let formatter = NumberFormatter()
            formatter.decimalSeparator = "."
            if invoiceText == nil || invoiceText?.trimmingCharacters(in: .whitespaces) == "" || self.amountTextField.text == nil || self.amountTextField.text?.trimmingCharacters(in: .whitespacesAndNewlines) == "" || CGFloat(truncating: formatter.number(from: self.amountTextField.text?.replacingOccurrences(of: ",", with: ".") ?? "0.0")!) == 0  {
                
                // Fields are left empty or the amount if set to zero.
                
            } else if CGFloat(truncating: formatter.number(from: self.amountTextField.text?.replacingOccurrences(of: ",", with: ".") ?? "0.0")!) > self.btcAmount {
                // Insufficient funds available.
                self.showErrorMessage(alertTitle: "Oops!", alertMessage: "Make sure the amount of BTC you wish to send is within your spendable balance.", alertButton: "Okay")
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
                let labelActualAmount = CGFloat(truncating: NumberFormatter().number(from: ((self.amountTextField.text ?? "0").replacingOccurrences(of: ".", with: Locale.current.decimalSeparator!).replacingOccurrences(of: ",", with: Locale.current.decimalSeparator!)))!)
                
                self.confirmAddressLabel.text = invoiceText
                self.confirmAmountLabel.text = "\(self.amountTextField.text ?? "0") btc"
                self.confirmEuroLabel.text = "\(Int(labelActualAmount*conversionRate)) \(currencySymbol)"
                
                if let actualBlockchain = LightningNodeService.shared.getBlockchain(), let actualWallet = LightningNodeService.shared.getWallet() {
                    
                    let actualAddress:String = invoiceText!
                    let actualAmount:Int = Int((CGFloat(truncating: NumberFormatter().number(from: ((self.amountTextField.text!).replacingOccurrences(of: ".", with: Locale.current.decimalSeparator!).replacingOccurrences(of: ",", with: Locale.current.decimalSeparator!)))!)*100000000).rounded())
                    
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
                            let txBuilder = TxBuilder().addRecipient(script: script, amount: UInt64(actualAmount))
                            let details = try txBuilder.finish(wallet: actualWallet)
                            let _ = try actualWallet.sign(psbt: details.psbt, signOptions: nil)
                            let tx = details.psbt.extractTx()
                            let size = tx.vsize()

                            print("Size: \(String(describing: size))")
                            print("High: \(self.feeHigh*Float(size)), Medium: \(self.feeMedium*Float(size)), Low: \(self.feeLow*Float(size))")
                            
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
                                
                                self.showErrorMessage(alertTitle: "Oops!", alertMessage: "We couldn't proceed to the next step. Error: \(error).", alertButton: "Okay")
                                
                                SentrySDK.capture(error: error)
                            }
                        } catch {
                            print("Error: \(error.localizedDescription)")
                            DispatchQueue.main.async {
                                self.nextLabel.alpha = 1
                                self.nextSpinner.stopAnimating()
                                
                                self.showErrorMessage(alertTitle: "Oops!", alertMessage: "We couldn't proceed to the next step. Error: \(error.localizedDescription).", alertButton: "Okay")
                                
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
        
        switch tappedFee {
        case "fast":
            self.fastView.backgroundColor = UIColor(white: 1, alpha: 1)
            self.mediumView.backgroundColor = UIColor(white: 1, alpha: 0.7)
            self.slowView.backgroundColor = UIColor(white: 1, alpha: 0.7)
            self.selectedFee = "high"
            
            if (CGFloat(truncating: NumberFormatter().number(from: ((self.satsFast.text!).replacingOccurrences(of: " sats", with: "").replacingOccurrences(of: ".", with: Locale.current.decimalSeparator!).replacingOccurrences(of: ",", with: Locale.current.decimalSeparator!)))!)) / (CGFloat(truncating: NumberFormatter().number(from: ((self.amountTextField.text!).replacingOccurrences(of: ".", with: Locale.current.decimalSeparator!).replacingOccurrences(of: ",", with: Locale.current.decimalSeparator!)))!)*100000000) > 0.1 {
                
                self.showErrorMessage(alertTitle: "High fee rate", alertMessage: "The fee you've selected costs more than 10 % of the bitcoin you're sending. Make sure this is as intended.", alertButton: "Okay")
            }
        case "medium":
            self.fastView.backgroundColor = UIColor(white: 1, alpha: 0.7)
            self.mediumView.backgroundColor = UIColor(white: 1, alpha: 1)
            self.slowView.backgroundColor = UIColor(white: 1, alpha: 0.7)
            self.selectedFee = "medium"
            
            if (CGFloat(truncating: NumberFormatter().number(from: ((self.satsMedium.text!).replacingOccurrences(of: " sats", with: "").replacingOccurrences(of: ".", with: Locale.current.decimalSeparator!).replacingOccurrences(of: ",", with: Locale.current.decimalSeparator!)))!)) / (CGFloat(truncating: NumberFormatter().number(from: ((self.amountTextField.text!).replacingOccurrences(of: ".", with: Locale.current.decimalSeparator!).replacingOccurrences(of: ",", with: Locale.current.decimalSeparator!)))!)*100000000) > 0.1 {
                
                self.showErrorMessage(alertTitle: "High fee rate", alertMessage: "The fee you've selected costs more than 10 % of the bitcoin you're sending. Make sure this is as intended.", alertButton: "Okay")
            }
        case "slow":
            self.fastView.backgroundColor = UIColor(white: 1, alpha: 0.7)
            self.mediumView.backgroundColor = UIColor(white: 1, alpha: 0.7)
            self.slowView.backgroundColor = UIColor(white: 1, alpha: 1)
            self.selectedFee = "low"
            
            if (CGFloat(truncating: NumberFormatter().number(from: ((self.satsSlow.text!).replacingOccurrences(of: " sats", with: "").replacingOccurrences(of: ".", with: Locale.current.decimalSeparator!).replacingOccurrences(of: ",", with: Locale.current.decimalSeparator!)))!)) / (CGFloat(truncating: NumberFormatter().number(from: ((self.amountTextField.text!).replacingOccurrences(of: ".", with: Locale.current.decimalSeparator!).replacingOccurrences(of: ",", with: Locale.current.decimalSeparator!)))!)*100000000) > 0.1 {
                
                self.showErrorMessage(alertTitle: "High fee rate", alertMessage: "The fee you've selected costs more than 10 % of the bitcoin you're sending. Make sure this is as intended.", alertButton: "Okay")
            }
        default:
            self.fastView.backgroundColor = UIColor(white: 1, alpha: 0.7)
            self.mediumView.backgroundColor = UIColor(white: 1, alpha: 1)
            self.slowView.backgroundColor = UIColor(white: 1, alpha: 0.7)
            self.selectedFee = "medium"
            
            if (CGFloat(truncating: NumberFormatter().number(from: ((self.satsMedium.text!).replacingOccurrences(of: " sats", with: "").replacingOccurrences(of: ".", with: Locale.current.decimalSeparator!).replacingOccurrences(of: ",", with: Locale.current.decimalSeparator!)))!)) / (CGFloat(truncating: NumberFormatter().number(from: ((self.amountTextField.text!).replacingOccurrences(of: ".", with: Locale.current.decimalSeparator!).replacingOccurrences(of: ",", with: Locale.current.decimalSeparator!)))!)*100000000) > 0.1 {
                
                self.showErrorMessage(alertTitle: "High fee rate", alertMessage: "The fee you've selected costs more than 10 % of the bitcoin you're sending. Make sure this is as intended.", alertButton: "Okay")
            }
        }
    }
    
    
    func confirmSendOnchain() {
        // Send onchain transaction.
        
        var feeSatoshis = (self.satsMedium.text ?? "no").replacingOccurrences(of: " sats", with: "")
        if self.selectedFee == "low" {
            feeSatoshis = (self.satsSlow.text ?? "no").replacingOccurrences(of: " sats", with: "")
        } else if self.selectedFee == "high" {
            feeSatoshis = (self.satsFast.text ?? "no").replacingOccurrences(of: " sats", with: "")
        }
        
        let alert = UIAlertController(title: "Send transaction", message: "Are you sure you want to send \(self.amountTextField.text ?? "these") btc, with a fee of \(feeSatoshis) satoshis, to \(self.confirmAddressLabel.text ?? "this address")?", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        alert.addAction(UIAlertAction(title: "Confirm", style: .default, handler: {_ in
            
            self.sendLabel.alpha = 0
            self.sendSpinner.startAnimating()
            
            if let actualWallet = LightningNodeService.shared.getWallet(), let actualBlockchain = LightningNodeService.shared.getBlockchain() {
                
                let actualAmount:Int = Int((CGFloat(truncating: NumberFormatter().number(from: ((self.amountTextField.text!).replacingOccurrences(of: ".", with: Locale.current.decimalSeparator!).replacingOccurrences(of: ",", with: Locale.current.decimalSeparator!)))!)*100000000).rounded())
                
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
                        let txBuilder = TxBuilder().addRecipient(script: script, amount: UInt64(actualAmount)).feeRate(satPerVbyte: selectedVbyte)
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
                            
                            let successAlert = UIAlertController(title: "Success", message: "Your transaction has been sent and will show up in your wallet shortly.", preferredStyle: .alert)
                            successAlert.addAction(UIAlertAction(title: "Okay", style: .default, handler: {_ in
                                
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
                                newTransaction.fee = Int(CGFloat(truncating: NumberFormatter().number(from: satsLabel!.text!.replacingOccurrences(of: " sats", with: "").replacingOccurrences(of: ".", with: Locale.current.decimalSeparator!).replacingOccurrences(of: ",", with: Locale.current.decimalSeparator!))!))
                                newTransaction.sent = actualAmount + newTransaction.fee
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
                        self.showErrorMessage(alertTitle: "Error", alertMessage: "We're unable to complete your transaction. We're receiving the following error message: \(error.localizedDescription).", alertButton: "Okay")
                    }
                }
            } else {
                print("Wallet or Blockchain instance not available.")
                self.showErrorMessage(alertTitle: "Error", alertMessage: "We're unable to complete your transaction. Please close and reopen our app and try again.", alertButton: "Okay")
            }
        }))
        self.present(alert, animated: true)
    }
    
    func showErrorMessage(alertTitle:String, alertMessage:String, alertButton:String) {
        DispatchQueue.main.async {
            let alert = UIAlertController(title: alertTitle, message: alertMessage, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: alertButton, style: .cancel, handler: nil))
            self.present(alert, animated: true)
        }
    }
}
