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
    
    func confirmLightningTransaction(lnurlinvoice:String?, sendVC:SendViewController?, receiveVC:ReceiveViewController?, lnurlNote:String?) {
        
        if self.checkInternetConnection() {
            var invoiceText = sendVC?.toTextField.text
            if lnurlinvoice != nil {
                invoiceText = lnurlinvoice!
            }
            
            // Pay lightning invoice.
            if invoiceText == nil || invoiceText?.trimmingCharacters(in: .whitespacesAndNewlines) == "" {
                // Invoice field was left empty.
            } else {
                
                let bitcoinValue = self.getCorrectBitcoinValue(coreVC: sendVC?.coreVC ?? receiveVC?.coreVC ?? CoreViewController())
                
                if invoiceText!.lowercased().contains("lnurl") || self.isValidEmail(invoiceText!.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)) {
                    // LNURL code.
                    self.handleLNURL(code: invoiceText!.replacingOccurrences(of: "lightning:", with: "").trimmingCharacters(in: .whitespacesAndNewlines), sendVC: sendVC, receiveVC: nil)
                    
                } else if let parsedInvoice = Bindings.Bolt11Invoice.fromStr(s: invoiceText!).getValue() {
                    // Lightning invoice.
                    if let invoiceAmountMilli = parsedInvoice.amountMilliSatoshis() {
                        let invoiceAmount = Int(invoiceAmountMilli)/1000
                        
                        // Calculate maximum total routing fees.
                        let invoicePaymentResult = Bindings.paymentParametersFromInvoice(invoice: parsedInvoice)
                        let (_, _, tryRouteParams) = invoicePaymentResult.getValue()!
                        let maximumRoutingFeesMsat:Int = Int(tryRouteParams.getMaxTotalRoutingFeeMsat() ?? 0)
                        let maximumRoutingFeesSat:Int = maximumRoutingFeesMsat/1000
                        
                        let transactionValue = CGFloat(invoiceAmount)/100000000
                        let convertedValue = String(CGFloat(Int(transactionValue*bitcoinValue.currentValue*100))/100)
                        
                        // Check if we have sufficient Lightning balance
                        let availableLightningBalance = sendVC?.maximumSendableLNSats ?? receiveVC?.homeVC?.coreVC?.bittrWallet.satoshisLightning ?? 0
                        if invoiceAmount > availableLightningBalance {
                            // Check if we have sufficient onchain balance for a swap
                            let availableOnchainBalance = sendVC?.homeVC?.coreVC?.bittrWallet.satoshisOnchain ?? receiveVC?.homeVC?.coreVC?.bittrWallet.satoshisOnchain ?? 0
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
                        sendVC?.temporaryInvoiceNote = lnurlNote
                        receiveVC?.temporaryInvoiceNote = lnurlNote
                        
                        self.showAlert(presentingController: self, title: Language.getWord(withID: "sendtransaction"), message: "\(Language.getWord(withID: "lightningconfirmation")) \(invoiceAmount) satoshis (\(bitcoinValue.chosenCurrency) \(convertedValue)) \(Language.getWord(withID: "lightningconfirmation2"))?\n\n\(Language.getWord(withID: "lightningconfirmation3")) \(maximumRoutingFeesSat) satoshis.", buttons: [Language.getWord(withID: "cancel"), Language.getWord(withID: "confirm")], actions: [nil, #selector(self.performLightningPayment)])
                    } else {
                        // Zero invoice.
                        let invoiceAmount = Int(self.stringToNumber(sendVC?.amountTextField.text))
                        if invoiceAmount > 0 {
                            
                            // Calculate maximum total routing fees.
                            let invoicePaymentResult = Bindings.paymentParametersFromZeroAmountInvoice(invoice: parsedInvoice, amountMsat: UInt64(invoiceAmount*1000))
                            let (_, _, tryRouteParams) = invoicePaymentResult.getValue()!
                            let maximumRoutingFeesMsat:Int = Int(tryRouteParams.getMaxTotalRoutingFeeMsat() ?? 0)
                            let maximumRoutingFeesSat:Int = maximumRoutingFeesMsat/1000
                            
                            let transactionValue = CGFloat(invoiceAmount)/100000000
                            let convertedValue = String(CGFloat(Int(transactionValue*bitcoinValue.currentValue*100))/100)
                            
                            // Check if we have sufficient Lightning balance
                            let availableLightningBalance = sendVC?.maximumSendableLNSats ?? receiveVC?.homeVC?.coreVC?.bittrWallet.satoshisLightning ?? 0
                            if invoiceAmount > availableLightningBalance {
                                // Check if we have sufficient onchain balance for a swap
                                let availableOnchainBalance = sendVC?.homeVC?.coreVC?.bittrWallet.satoshisOnchain ?? receiveVC?.homeVC?.coreVC?.bittrWallet.satoshisOnchain ?? 0
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
                            sendVC?.temporaryInvoiceNote = lnurlNote
                            receiveVC?.temporaryInvoiceNote = lnurlNote
                            
                            self.showAlert(presentingController: self, title: Language.getWord(withID: "sendtransaction"), message: "\(Language.getWord(withID: "lightningconfirmation")) \(invoiceAmount) satoshis (\(bitcoinValue.chosenCurrency) \(convertedValue)) \(Language.getWord(withID: "lightningconfirmation2"))?\n\n\(Language.getWord(withID: "lightningconfirmation3")) \(maximumRoutingFeesSat) satoshis.", buttons: [Language.getWord(withID: "cancel"), Language.getWord(withID: "confirm")], actions: [nil, #selector(self.performZeroLightningPayment)])
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
                let paymentHash = try await LightningNodeService.shared.sendPayment(invoice: Bolt11Invoice.fromStr(invoiceStr: String(invoiceText.replacingOccurrences(of: " ", with: ""))))
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    
                    if let thisPayment = LightningNodeService.shared.getPaymentDetails(paymentHash: paymentHash) {
                        
                        if thisPayment.status != .failed {
                            (sendVC ?? receiveVC!).addNewPaymentToTable(paymentHash: paymentHash, invoiceAmount: invoiceAmount, delegate: (sendVC ?? receiveVC!))
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
                
                let paymentHash = try await LightningNodeService.shared.sendZeroAmountPayment(invoice: Bolt11Invoice.fromStr(invoiceStr: String(invoiceText.replacingOccurrences(of: " ", with: ""))), amount: invoiceAmount)
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    
                    if let thisPayment = LightningNodeService.shared.getPaymentDetails(paymentHash: paymentHash) {
                        
                        if thisPayment.status != .failed {
                            (sendVC ?? receiveVC!).addNewPaymentToTable(paymentHash: paymentHash, invoiceAmount: invoiceAmount, delegate: (sendVC ?? receiveVC!))
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
            
            var coreVC:CoreViewController?
            if let sendVC = delegate as? SendViewController { coreVC = sendVC.coreVC } else if let receiveVC = delegate as? ReceiveViewController { coreVC = receiveVC.coreVC } else if let swapVC = delegate as? SwapViewController { coreVC = swapVC.coreVC }
            let newTransaction = self.createTransaction(transactionDetails: nil, paymentDetails: thisPayment, bittrTransaction: nil, coreVC: coreVC, bittrTransactions: nil)
            
            if Int(thisPayment.amountMsat ?? 0)/1000 > invoiceAmount {
                // Fees were incurred.
                let feesIncurred = (Int(thisPayment.amountMsat ?? 0)/1000) - invoiceAmount
                CacheManager.storePaymentFees(hash: thisPayment.kind.preimageAsString ?? thisPayment.id, fees: feesIncurred)
                newTransaction.fee = feesIncurred
            } else {
                newTransaction.fee = 0
            }
            
            if let sendVC = delegate as? SendViewController {
                if sendVC.temporaryInvoiceNote != nil {
                    CacheManager.storeTransactionNote(txid: thisPayment.kind.preimageAsString ?? thisPayment.id, note: sendVC.temporaryInvoiceNote!)
                    sendVC.temporaryInvoiceNote = nil
                }
                sendVC.completedTransaction = newTransaction
                sendVC.homeVC?.addLightningTransaction(thisTransaction: newTransaction, paymentDetails: thisPayment)
                sendVC.performSegue(withIdentifier: "SendToTransaction", sender: self)
            } else if let receiveVC = delegate as? ReceiveViewController {
                if receiveVC.temporaryInvoiceNote != nil {
                    CacheManager.storeTransactionNote(txid: thisPayment.kind.preimageAsString ?? thisPayment.id, note: receiveVC.temporaryInvoiceNote!)
                    receiveVC.temporaryInvoiceNote = nil
                }
                receiveVC.completedTransaction = newTransaction
                receiveVC.homeVC?.addLightningTransaction(thisTransaction: newTransaction, paymentDetails: thisPayment)
                receiveVC.performSegue(withIdentifier: "ReceiveToTransaction", sender: self)
            } else if let swapVC = delegate as? SwapViewController {
                swapVC.homeVC?.addLightningTransaction(thisTransaction: newTransaction, paymentDetails: thisPayment)
            }
            
        }
    }
}
