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
    
    func confirmLightningTransaction() {
        
        if self.checkInternetConnection() {
            var invoiceText = self.toTextField.text
            if self.selectedInput != "keyboard" {
                invoiceText = self.invoiceLabel.text
            }
            
            // Pay lightning invoice.
            if invoiceText == nil || invoiceText?.trimmingCharacters(in: .whitespacesAndNewlines) == "" {
                // Invoice field was left empty.
            } else {
                
                if let parsedInvoice = Bindings.Bolt11Invoice.fromStr(s: invoiceText!).getValue() {
                    if let invoiceAmountMilli = parsedInvoice.amountMilliSatoshis() {
                        let invoiceAmount = Int(invoiceAmountMilli)/1000
                        
                        var correctValue:CGFloat = self.eurValue
                        var currencySymbol = "€"
                        if UserDefaults.standard.value(forKey: "currency") as? String == "CHF" {
                            correctValue = self.chfValue
                            currencySymbol = "CHF"
                        }
                        
                        var transactionValue = CGFloat(invoiceAmount)/100000000
                        var convertedValue = String(CGFloat(Int(transactionValue*correctValue*100))/100)
                        
                        let alert = UIAlertController(title: "Send transaction", message: "Are you sure you want to pay \(invoiceAmount) satoshis (\(currencySymbol) \(convertedValue)) for this invoice?", preferredStyle: .alert)
                        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
                        alert.addAction(UIAlertAction(title: "Confirm", style: .default, handler: {_ in
                            
                            self.nextLabel.alpha = 0
                            self.nextSpinner.startAnimating()
                            
                            Task {
                                do {
                                    let paymentHash = try await LightningNodeService.shared.sendPayment(invoice: String(invoiceText!.replacingOccurrences(of: " ", with: "")))
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                                        
                                        if let thisPayment = LightningNodeService.shared.getPaymentDetails(paymentHash: paymentHash) {
                                            
                                            if thisPayment.status != .failed {
                                                // Success alert
                                                let alert = UIAlertController(title: "Payment successful", message: "Payment hash: \(paymentHash)", preferredStyle: .alert)
                                                alert.addAction(UIAlertAction(title: "Okay", style: .default, handler: { _ in
                                                    
                                                    if let thisPayment = LightningNodeService.shared.getPaymentDetails(paymentHash: paymentHash) {
                                                        
                                                        let newTransaction = Transaction()
                                                        newTransaction.id = thisPayment.preimage ?? paymentHash
                                                        newTransaction.sent = Int(thisPayment.amountMsat ?? 0)/1000
                                                        newTransaction.received = 0
                                                        newTransaction.isLightning = true
                                                        newTransaction.timestamp = Int(Date().timeIntervalSince1970)
                                                        newTransaction.confirmations = 0
                                                        newTransaction.height = 0
                                                        newTransaction.fee = 0
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
                                                    }
                                                }))
                                                self.present(alert, animated: true)
                                            } else {
                                                // Payment came back failed.
                                                let alert = UIAlertController(title: "Payment failed", message: "We were able to broadcast your payment, but it failed.\n\nIf funds were recently deposited into your Lightning wallet, it may take some time for these to be confirmed and available for sending elsewhere.", preferredStyle: .alert)
                                                alert.addAction(UIAlertAction(title: "Okay", style: .default))
                                                self.present(alert, animated: true)
                                            }
                                        } else {
                                            // Success alert
                                            let alert = UIAlertController(title: "Payment successful", message: "Payment hash: \(paymentHash)", preferredStyle: .alert)
                                            alert.addAction(UIAlertAction(title: "Okay", style: .default))
                                            self.present(alert, animated: true)
                                        }
                                        
                                        self.nextLabel.alpha = 1
                                        self.nextSpinner.stopAnimating()
                                        self.toTextField.text = nil
                                        
                                        self.invoiceLabel.text = nil
                                        self.toTextFieldHeight.constant = 0
                                        self.toTextField.text = nil
                                        self.amountTextField.text = nil
                                        self.toTextFieldTop.constant = 5
                                        self.invoiceLabelTop.constant = 10
                                    }
                                } catch let error as NodeError {
                                    let errorString = handleNodeError(error)
                                    DispatchQueue.main.async {
                                        // Error alert for NodeError
                                        
                                        self.nextLabel.alpha = 1
                                        self.nextSpinner.stopAnimating()
                                        
                                        let alert = UIAlertController(title: "Payment Error", message: errorString.detail, preferredStyle: .alert)
                                        alert.addAction(UIAlertAction(title: "Okay", style: .default))
                                        self.present(alert, animated: true)
                                        
                                        SentrySDK.capture(error: error)
                                    }
                                } catch {
                                    DispatchQueue.main.async {
                                        // General error alert
                                        
                                        self.nextLabel.alpha = 1
                                        self.nextSpinner.stopAnimating()
                                        
                                        let alert = UIAlertController(title: "Unexpected Error", message: error.localizedDescription, preferredStyle: .alert)
                                        alert.addAction(UIAlertAction(title: "Okay", style: .default))
                                        self.present(alert, animated: true)
                                        
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
