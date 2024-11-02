//
//  SendLightning.swift
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
    
    func confirmLightningTransaction(lnurlinvoice:String?) {
        
        if self.checkInternetConnection() {
            var invoiceText = self.toTextField.text
            if self.selectedInput != "keyboard" {
                invoiceText = self.invoiceLabel.text
            }
            if lnurlinvoice != nil {
                invoiceText = lnurlinvoice!
            }
            
            // Pay lightning invoice.
            if invoiceText == nil || invoiceText?.trimmingCharacters(in: .whitespacesAndNewlines) == "" {
                // Invoice field was left empty.
            } else {
                
                if invoiceText!.lowercased().contains("lnurl") || self.isValidEmail(invoiceText!.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)) {
                    // LNURL code.
                    self.handleLNURL(code: invoiceText!.replacingOccurrences(of: "lightning:", with: "").trimmingCharacters(in: .whitespacesAndNewlines), sendVC: self, receiveVC: nil)
                    
                } else if let parsedInvoice = Bindings.Bolt11Invoice.fromStr(s: invoiceText!).getValue() {
                    // Lightning invoice.
                    if let invoiceAmountMilli = parsedInvoice.amountMilliSatoshis() {
                        let invoiceAmount = Int(invoiceAmountMilli)/1000
                        
                        var correctValue:CGFloat = self.eurValue
                        var currencySymbol = "€"
                        if UserDefaults.standard.value(forKey: "currency") as? String == "CHF" {
                            correctValue = self.chfValue
                            currencySymbol = "CHF"
                        }
                        
                        // Calculate maximum total routing fees.
                        let invoicePaymentResult = Bindings.paymentParametersFromInvoice(invoice: parsedInvoice)
                        let (tryPaymentHash, tryRecipientOnion, tryRouteParams) = invoicePaymentResult.getValue()!
                        let maximumRoutingFeesMsat:Int = Int(tryRouteParams.getMaxTotalRoutingFeeMsat() ?? 0)
                        let maximumRoutingFeesSat:Int = maximumRoutingFeesMsat/1000
                        
                        var transactionValue = CGFloat(invoiceAmount)/100000000
                        var convertedValue = String(CGFloat(Int(transactionValue*correctValue*100))/100)
                        
                        let alert = UIAlertController(title: Language.getWord(withID: "sendtransaction"), message: "\(Language.getWord(withID: "lightningconfirmation")) \(invoiceAmount) satoshis (\(currencySymbol) \(convertedValue)) \(Language.getWord(withID: "lightningconfirmation2"))?\n\n\(Language.getWord(withID: "lightningconfirmation3")) \(maximumRoutingFeesSat) satoshis.", preferredStyle: .alert)
                        alert.addAction(UIAlertAction(title: Language.getWord(withID: "cancel"), style: .cancel, handler: nil))
                        alert.addAction(UIAlertAction(title: Language.getWord(withID: "confirm"), style: .default, handler: {_ in
                            
                            self.nextLabel.alpha = 0
                            self.nextSpinner.startAnimating()
                            
                            print("Invoice text: " + String(invoiceText!.replacingOccurrences(of: " ", with: "")))
                            
                            Task {
                                do {
                                    let paymentHash = try await LightningNodeService.shared.sendPayment(invoice: String(invoiceText!.replacingOccurrences(of: " ", with: "")))
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                                        
                                        if let thisPayment = LightningNodeService.shared.getPaymentDetails(paymentHash: paymentHash) {
                                            
                                            if thisPayment.status != .failed {
                                                // Success alert
                                                let alert = UIAlertController(title: Language.getWord(withID: "paymentsuccessful"), message: "Payment hash: \(paymentHash)", preferredStyle: .alert)
                                                alert.addAction(UIAlertAction(title: Language.getWord(withID: "okay"), style: .default, handler: { _ in
                                                    
                                                    if let thisPayment = LightningNodeService.shared.getPaymentDetails(paymentHash: paymentHash) {
                                                        
                                                        let newTransaction = Transaction()
                                                        newTransaction.id = thisPayment.id
                                                        newTransaction.sent = Int(thisPayment.amountMsat ?? 0)/1000
                                                        newTransaction.received = 0
                                                        newTransaction.isLightning = true
                                                        newTransaction.timestamp = Int(Date().timeIntervalSince1970)
                                                        newTransaction.confirmations = 0
                                                        newTransaction.height = 0
                                                        newTransaction.isBittr = false
                                                        
                                                        if Int(thisPayment.amountMsat ?? 0)/1000 > invoiceAmount {
                                                            // Fees were incurred.
                                                            let feesIncurred = (Int(thisPayment.amountMsat ?? 0)/1000) - invoiceAmount
                                                            CacheManager.storePaymentFees(hash: thisPayment.id, fees: feesIncurred)
                                                            newTransaction.fee = feesIncurred
                                                        } else {
                                                            newTransaction.fee = 0
                                                        }
                                                        
                                                        self.completedTransaction = newTransaction
                                                        
                                                        if let actualHomeVC = self.homeVC {
                                                            actualHomeVC.setTransactions += [newTransaction]
                                                            actualHomeVC.setTransactions.sort { transaction1, transaction2 in
                                                                transaction1.timestamp > transaction2.timestamp
                                                            }
                                                            actualHomeVC.homeTableView.reloadData()
                                                        }
                                                        
                                                        self.performSegue(withIdentifier: "SendToTransaction", sender: self)
                                                    }
                                                }))
                                                self.present(alert, animated: true)
                                            } else {
                                                // Payment came back failed.
                                                self.showErrorMessage(alertTitle: Language.getWord(withID: "paymentfailed"), alertMessage: Language.getWord(withID: "paymentfailed2"), alertButton: Language.getWord(withID: "okay"))
                                            }
                                        } else {
                                            // Success alert
                                            self.showErrorMessage(alertTitle: Language.getWord(withID: "paymentsuccessful"), alertMessage: "Payment hash: \(paymentHash)", alertButton: Language.getWord(withID: "okay"))
                                        }
                                        
                                        self.nextLabel.alpha = 1
                                        self.nextSpinner.stopAnimating()
                                        
                                        self.resetFields()
                                    }
                                } catch let error as NodeError {
                                    let errorString = handleNodeError(error)
                                    DispatchQueue.main.async {
                                        // Error alert for NodeError
                                        
                                        self.nextLabel.alpha = 1
                                        self.nextSpinner.stopAnimating()
                                        
                                        self.showErrorMessage(alertTitle: Language.getWord(withID: "paymentfailed"), alertMessage: errorString.detail, alertButton: Language.getWord(withID: "okay"))
                                        
                                        SentrySDK.capture(error: error)
                                    }
                                } catch {
                                    DispatchQueue.main.async {
                                        // General error alert
                                        
                                        self.nextLabel.alpha = 1
                                        self.nextSpinner.stopAnimating()
                                        
                                        self.showErrorMessage(alertTitle: Language.getWord(withID: "unexpectederror"), alertMessage: error.localizedDescription, alertButton: Language.getWord(withID: "okay"))
                                        
                                        SentrySDK.capture(error: error)
                                    }
                                }
                            }
                        }))
                        self.present(alert, animated: true)
                    }
                }
            }
        }
    }
}
