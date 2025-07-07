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

extension UIViewController {
    
    func confirmLightningTransaction(lnurlinvoice:String?, sendVC:SendViewController?, receiveVC:ReceiveViewController?) {
        
        if self.checkInternetConnection() {
            var invoiceText = sendVC?.toTextField.text
            if lnurlinvoice != nil {
                invoiceText = lnurlinvoice!
            }
            
            // Pay lightning invoice.
            if invoiceText == nil || invoiceText?.trimmingCharacters(in: .whitespacesAndNewlines) == "" {
                // Invoice field was left empty.
            } else {
                
                if invoiceText!.lowercased().contains("lnurl") || self.isValidEmail(invoiceText!.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)) {
                    // LNURL code.
                    self.handleLNURL(code: invoiceText!.replacingOccurrences(of: "lightning:", with: "").trimmingCharacters(in: .whitespacesAndNewlines), sendVC: sendVC, receiveVC: nil)
                    
                } else if let parsedInvoice = Bindings.Bolt11Invoice.fromStr(s: invoiceText!).getValue() {
                    // Lightning invoice.
                    if let invoiceAmountMilli = parsedInvoice.amountMilliSatoshis() {
                        let invoiceAmount = Int(invoiceAmountMilli)/1000
                        
                        var correctValue:CGFloat = CGFloat(sendVC?.eurValue ?? receiveVC?.homeVC?.coreVC?.eurValue ?? 0)
                        var currencySymbol = "€"
                        if UserDefaults.standard.value(forKey: "currency") as? String == "CHF" {
                            correctValue = CGFloat(sendVC?.chfValue ?? receiveVC?.homeVC?.coreVC?.eurValue ?? 0)
                            currencySymbol = "CHF"
                        }
                        
                        // Calculate maximum total routing fees.
                        let invoicePaymentResult = Bindings.paymentParametersFromInvoice(invoice: parsedInvoice)
                        let (tryPaymentHash, tryRecipientOnion, tryRouteParams) = invoicePaymentResult.getValue()!
                        let maximumRoutingFeesMsat:Int = Int(tryRouteParams.getMaxTotalRoutingFeeMsat() ?? 0)
                        let maximumRoutingFeesSat:Int = maximumRoutingFeesMsat/1000
                        
                        var transactionValue = CGFloat(invoiceAmount)/100000000
                        var convertedValue = String(CGFloat(Int(transactionValue*correctValue*100))/100)
                        
                        // Check if we have sufficient Lightning balance
                        let availableLightningBalance = sendVC?.maximumSendableLNSats ?? receiveVC?.homeVC?.coreVC?.lightningBalanceInSats ?? 0
                        if invoiceAmount > availableLightningBalance {
                            // Check if we have sufficient onchain balance for a swap
                            let availableOnchainBalance = sendVC?.homeVC?.coreVC?.onchainBalanceInSats ?? receiveVC?.homeVC?.coreVC?.onchainBalanceInSats ?? 0
                            if availableOnchainBalance >= invoiceAmount {
                                // Suggest swap to Lightning
                                self.showAlert(
                                    presentingController: self, 
                                    title: Language.getWord(withID: "insufficientfunds"), 
                                    message: "\(Language.getWord(withID: "lightninginsufficientfunds")) \(availableLightningBalance) satoshis.\n\n\(Language.getWord(withID: "swapinsufficientfunds")) \(availableOnchainBalance) satoshis.", 
                                    buttons: [Language.getWord(withID: "cancel"), Language.getWord(withID: "swapandpay")], 
                                    actions: [#selector(self.cancelSwapOffer), #selector(self.swapAndPayLightning)]
                                )
                                // Store the invoice for the swap
                                sendVC?.pendingLightningInvoice = invoiceText!
                                receiveVC?.pendingLightningInvoice = invoiceText!
                                return
                            } else {
                                // Insufficient funds in both Lightning and onchain
                                self.showAlert(presentingController: self, title: Language.getWord(withID: "insufficientfunds"), message: "\(Language.getWord(withID: "lightninginsufficientfunds")) \(availableLightningBalance) satoshis.", buttons: [Language.getWord(withID: "okay")], actions: nil)
                                return
                            }
                        }
                        
                        sendVC?.temporaryInvoiceText = invoiceText!
                        receiveVC?.temporaryInvoiceText = invoiceText!
                        sendVC?.temporaryInvoiceAmount = invoiceAmount
                        receiveVC?.temporaryInvoiceAmount = invoiceAmount
                        
                        self.showAlert(presentingController: self, title: Language.getWord(withID: "sendtransaction"), message: "\(Language.getWord(withID: "lightningconfirmation")) \(invoiceAmount) satoshis (\(currencySymbol) \(convertedValue)) \(Language.getWord(withID: "lightningconfirmation2"))?\n\n\(Language.getWord(withID: "lightningconfirmation3")) \(maximumRoutingFeesSat) satoshis.", buttons: [Language.getWord(withID: "cancel"), Language.getWord(withID: "confirm")], actions: [nil, #selector(self.performLightningPayment)])
                    } else {
                        // Zero invoice.
                        let invoiceAmount = Int(self.stringToNumber(sendVC?.amountTextField.text))
                        if invoiceAmount > 0 {
                            
                            var correctValue:CGFloat = CGFloat(sendVC?.eurValue ?? receiveVC?.homeVC?.coreVC?.eurValue ?? 0)
                            var currencySymbol = "€"
                            if UserDefaults.standard.value(forKey: "currency") as? String == "CHF" {
                                correctValue = CGFloat(sendVC?.chfValue ?? receiveVC?.homeVC?.coreVC?.eurValue ?? 0)
                                currencySymbol = "CHF"
                            }
                            
                            // Calculate maximum total routing fees.
                            let invoicePaymentResult = Bindings.paymentParametersFromZeroAmountInvoice(invoice: parsedInvoice, amountMsat: UInt64(invoiceAmount*1000))
                            let (tryPaymentHash, tryRecipientOnion, tryRouteParams) = invoicePaymentResult.getValue()!
                            let maximumRoutingFeesMsat:Int = Int(tryRouteParams.getMaxTotalRoutingFeeMsat() ?? 0)
                            let maximumRoutingFeesSat:Int = maximumRoutingFeesMsat/1000
                            
                            var transactionValue = CGFloat(invoiceAmount)/100000000
                            var convertedValue = String(CGFloat(Int(transactionValue*correctValue*100))/100)
                            
                            // Check if we have sufficient Lightning balance
                            let availableLightningBalance = sendVC?.maximumSendableLNSats ?? receiveVC?.homeVC?.coreVC?.lightningBalanceInSats ?? 0
                            if invoiceAmount > availableLightningBalance {
                                // Check if we have sufficient onchain balance for a swap
                                let availableOnchainBalance = sendVC?.homeVC?.coreVC?.onchainBalanceInSats ?? receiveVC?.homeVC?.coreVC?.onchainBalanceInSats ?? 0
                                if availableOnchainBalance >= invoiceAmount {
                                    // Suggest swap to Lightning
                                    self.showAlert(
                                        presentingController: self, 
                                        title: Language.getWord(withID: "insufficientfunds"), 
                                        message: "\(Language.getWord(withID: "lightninginsufficientfunds")) \(availableLightningBalance) satoshis.\n\n\(Language.getWord(withID: "swapinsufficientfunds")) \(availableOnchainBalance) satoshis.", 
                                        buttons: [Language.getWord(withID: "cancel"), Language.getWord(withID: "swapandpay")], 
                                        actions: [nil, #selector(self.swapAndPayLightning)]
                                    )
                                    // Store the invoice for the swap
                                    sendVC?.pendingLightningInvoice = invoiceText!
                                    receiveVC?.pendingLightningInvoice = invoiceText!
                                    return
                                } else {
                                    // Insufficient funds in both Lightning and onchain
                                    self.showAlert(presentingController: self, title: Language.getWord(withID: "insufficientfunds"), message: "\(Language.getWord(withID: "lightninginsufficientfunds")) \(availableLightningBalance) satoshis.", buttons: [Language.getWord(withID: "okay")], actions: nil)
                                    return
                                }
                            }
                            
                            sendVC?.temporaryInvoiceText = invoiceText!
                            receiveVC?.temporaryInvoiceText = invoiceText!
                            sendVC?.temporaryInvoiceAmount = invoiceAmount
                            receiveVC?.temporaryInvoiceAmount = invoiceAmount
                            
                            self.showAlert(presentingController: self, title: Language.getWord(withID: "sendtransaction"), message: "\(Language.getWord(withID: "lightningconfirmation")) \(invoiceAmount) satoshis (\(currencySymbol) \(convertedValue)) \(Language.getWord(withID: "lightningconfirmation2"))?\n\n\(Language.getWord(withID: "lightningconfirmation3")) \(maximumRoutingFeesSat) satoshis.", buttons: [Language.getWord(withID: "cancel"), Language.getWord(withID: "confirm")], actions: [nil, #selector(self.performZeroLightningPayment)])
                        }
                    }
                }
            }
        }
    }
    
    @objc func performLightningPayment() {
        self.hideAlert()
        
        let sendVC = self as? SendViewController
        let receiveVC = self as? ReceiveViewController
        
        sendVC?.nextLabel.alpha = 0
        sendVC?.nextSpinner.startAnimating()
        
        let invoiceText = sendVC?.temporaryInvoiceText ?? receiveVC!.temporaryInvoiceText
        sendVC?.temporaryInvoiceText = ""
        receiveVC?.temporaryInvoiceText = ""
        let invoiceAmount = sendVC?.temporaryInvoiceAmount ?? receiveVC!.temporaryInvoiceAmount
        sendVC?.temporaryInvoiceAmount = 0
        receiveVC?.temporaryInvoiceAmount = 0
        
        print("Invoice text: " + String(invoiceText.replacingOccurrences(of: " ", with: "")))
        
        Task {
            do {
                let paymentHash = try await LightningNodeService.shared.sendPayment(invoice: String(invoiceText.replacingOccurrences(of: " ", with: "")))
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    
                    if let thisPayment = LightningNodeService.shared.getPaymentDetails(paymentHash: paymentHash) {
                        
                        if thisPayment.status != .failed {
                            
                            var thisAction:Selector?
                            if sendVC != nil {
                                sendVC!.newPaymentHash = paymentHash
                                sendVC!.newInvoiceAmount = invoiceAmount
                                thisAction = #selector(sendVC!.addNewPayment)
                            } else if receiveVC != nil {
                                receiveVC!.newPaymentHash = paymentHash
                                receiveVC!.newInvoiceAmount = invoiceAmount
                                thisAction = #selector(receiveVC!.addNewPayment)
                            }
                            
                            if thisAction != nil {
                                // Success alert
                                self.showAlert(presentingController: self, title: Language.getWord(withID: "paymentsuccessful"), message: "Payment hash: \(paymentHash)", buttons: [Language.getWord(withID: "okay")], actions: [thisAction!])
                            }
                        } else {
                            // Payment came back failed.
                            self.showAlert(presentingController: self, title: Language.getWord(withID: "paymentfailed"), message: Language.getWord(withID: "paymentfailed2"), buttons: [Language.getWord(withID: "okay")], actions: nil)
                        }
                    } else {
                        // Success alert
                        self.showAlert(presentingController: self, title: Language.getWord(withID: "paymentsuccessful"), message: "Payment hash: \(paymentHash)", buttons: [Language.getWord(withID: "okay")], actions: nil)
                    }
                    
                    sendVC?.nextLabel.alpha = 1
                    sendVC?.nextSpinner.stopAnimating()
                    
                    sendVC?.resetFields()
                }
            } catch let error as NodeError {
                let errorString = handleNodeError(error)
                DispatchQueue.main.async {
                    // Error alert for NodeError
                    
                    sendVC?.nextLabel.alpha = 1
                    sendVC?.nextSpinner.stopAnimating()
                    
                    self.showAlert(presentingController: self, title: Language.getWord(withID: "paymentfailed"), message: errorString.detail, buttons: [Language.getWord(withID: "okay")], actions: nil)
                    
                    SentrySDK.capture(error: error)
                }
            } catch {
                DispatchQueue.main.async {
                    // General error alert
                    
                    sendVC?.nextLabel.alpha = 1
                    sendVC?.nextSpinner.stopAnimating()
                    
                    self.showAlert(presentingController: self, title: Language.getWord(withID: "unexpectederror"), message: error.localizedDescription, buttons: [Language.getWord(withID: "okay")], actions: nil)
                    
                    SentrySDK.capture(error: error)
                }
            }
        }
    }
    
    @objc func cancelSwapOffer() {
        self.hideAlert()
        print("DEBUG - cancelSwapOffer called, clearing pending data")
        
        let sendVC = self as? SendViewController
        let receiveVC = self as? ReceiveViewController
        
        // Clear the pending data when user cancels the swap offer
        sendVC?.pendingLightningInvoice = ""
        receiveVC?.pendingLightningInvoice = ""
        // Also clear the amount field to make it obvious this is cancelled
        sendVC?.amountTextField.text = ""   
    }
    
    @objc func swapAndPayLightning() {
        self.hideAlert()
        
        let sendVC = self as? SendViewController
        let receiveVC = self as? ReceiveViewController
        
        // Navigate to swap screen with the pending invoice using existing segue pattern
        if let homeVC = sendVC?.homeVC ?? receiveVC?.homeVC {
            // Store the pending invoice in a way that can be accessed by the swap screen
            let pendingInvoice = sendVC?.pendingLightningInvoice ?? receiveVC?.pendingLightningInvoice ?? ""
            
            // First dismiss the current view controller
            self.dismiss(animated: true) {
                // Then navigate through the existing segue pattern
                homeVC.performSegue(withIdentifier: "HomeToMove", sender: homeVC)
                
                // After a short delay, trigger the swap button tap to go directly to swap
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    if let moveVC = homeVC.presentedViewController as? MoveViewController {
                        // Set a flag to indicate this is from a Lightning payment
                        moveVC.isFromLightningPayment = true
                        moveVC.pendingLightningInvoice = pendingInvoice
                        moveVC.performSegue(withIdentifier: "MoveToSwap", sender: moveVC)
                    }
                }
            }
        }
    }
    
    @objc func performZeroLightningPayment() {
        self.hideAlert()
        
        let sendVC = self as? SendViewController
        let receiveVC = self as? ReceiveViewController
        
        sendVC?.nextLabel.alpha = 0
        sendVC?.nextSpinner.startAnimating()
        
        let invoiceText = sendVC?.temporaryInvoiceText ?? receiveVC!.temporaryInvoiceText
        sendVC?.temporaryInvoiceText = ""
        receiveVC?.temporaryInvoiceText = ""
        let invoiceAmount = sendVC?.temporaryInvoiceAmount ?? receiveVC!.temporaryInvoiceAmount
        sendVC?.temporaryInvoiceAmount = 0
        receiveVC?.temporaryInvoiceAmount = 0
        
        print("Invoice text: " + String(invoiceText.replacingOccurrences(of: " ", with: "")))
        
        Task {
            do {
                
                let paymentHash = try await LightningNodeService.shared.sendZeroAmountPayment(invoice: String(invoiceText.replacingOccurrences(of: " ", with: "")), amount: invoiceAmount)
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    
                    if let thisPayment = LightningNodeService.shared.getPaymentDetails(paymentHash: paymentHash) {
                        
                        if thisPayment.status != .failed {
                            
                            var thisAction:Selector?
                            if sendVC != nil {
                                sendVC!.newPaymentHash = paymentHash
                                sendVC!.newInvoiceAmount = invoiceAmount
                                thisAction = #selector(sendVC!.addNewPayment)
                            } else if receiveVC != nil {
                                receiveVC!.newPaymentHash = paymentHash
                                receiveVC!.newInvoiceAmount = invoiceAmount
                                thisAction = #selector(receiveVC!.addNewPayment)
                            }
                            
                            if thisAction != nil {
                                // Success alert
                                self.showAlert(presentingController: self, title: Language.getWord(withID: "paymentsuccessful"), message: "Payment hash: \(paymentHash)", buttons: [Language.getWord(withID: "okay")], actions: [thisAction!])
                            }
                        } else {
                            // Payment came back failed.
                            self.showAlert(presentingController: self, title: Language.getWord(withID: "paymentfailed"), message: Language.getWord(withID: "paymentfailed2"), buttons: [Language.getWord(withID: "okay")], actions: nil)
                        }
                    } else {
                        // Success alert
                        self.showAlert(presentingController: self, title: Language.getWord(withID: "paymentsuccessful"), message: "Payment hash: \(paymentHash)", buttons: [Language.getWord(withID: "okay")], actions: nil)
                    }
                    
                    sendVC?.nextLabel.alpha = 1
                    sendVC?.nextSpinner.stopAnimating()
                    
                    sendVC?.resetFields()
                }
            } catch let error as NodeError {
                let errorString = handleNodeError(error)
                DispatchQueue.main.async {
                    // Error alert for NodeError
                    
                    sendVC?.nextLabel.alpha = 1
                    sendVC?.nextSpinner.stopAnimating()
                    
                    self.showAlert(presentingController: self, title: Language.getWord(withID: "paymentfailed"), message: errorString.detail, buttons: [Language.getWord(withID: "okay")], actions: nil)
                    
                    SentrySDK.capture(error: error)
                }
            } catch {
                DispatchQueue.main.async {
                    // General error alert
                    
                    sendVC?.nextLabel.alpha = 1
                    sendVC?.nextSpinner.stopAnimating()
                    
                    self.showAlert(presentingController: self, title: Language.getWord(withID: "unexpectederror"), message: error.localizedDescription, buttons: [Language.getWord(withID: "okay")], actions: nil)
                    
                    SentrySDK.capture(error: error)
                }
            }
        }
    }
    
    func addNewPaymentToTable(paymentHash:PaymentHash, invoiceAmount:Int, delegate:Any?) {
        self.hideAlert()
        
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
            
            if let sendVC = delegate as? SendViewController {
                sendVC.completedTransaction = newTransaction
                if let homeVC = sendVC.homeVC {
                    homeVC.setTransactions += [newTransaction]
                    homeVC.setTransactions.sort { transaction1, transaction2 in
                        transaction1.timestamp > transaction2.timestamp
                    }
                    homeVC.homeTableView.reloadData()
                }
                sendVC.performSegue(withIdentifier: "SendToTransaction", sender: self)
            } else if let receiveVC = delegate as? ReceiveViewController {
                receiveVC.completedTransaction = newTransaction
                if let homeVC = receiveVC.homeVC {
                    homeVC.setTransactions += [newTransaction]
                    homeVC.setTransactions.sort { transaction1, transaction2 in
                        transaction1.timestamp > transaction2.timestamp
                    }
                    homeVC.homeTableView.reloadData()
                }
                receiveVC.performSegue(withIdentifier: "ReceiveToTransaction", sender: self)
            } else if let swapVC = delegate as? SwapViewController {
                if let homeVC = swapVC.homeVC {
                    homeVC.setTransactions += [newTransaction]
                    homeVC.setTransactions.sort { transaction1, transaction2 in
                        transaction1.timestamp > transaction2.timestamp
                    }
                    homeVC.homeTableView.reloadData()
                }
            }
            
        }
    }
}
