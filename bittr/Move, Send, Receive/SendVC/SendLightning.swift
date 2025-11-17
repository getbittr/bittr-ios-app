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
            // Set LNURL invoice or manually pasted invoice.
            let invoiceText = lnurlinvoice ?? sendVC?.toTextField.text
            
            // Pay lightning invoice.
            if invoiceText == nil || invoiceText?.trimmingCharacters(in: .whitespacesAndNewlines) == "" {
                // Invoice field was left empty.
            } else {
                
                // Get current bitcoin value.
                let bitcoinValue = self.getCorrectBitcoinValue(coreVC: sendVC?.coreVC ?? receiveVC?.coreVC ?? CoreViewController())
                
                // Check for LNURL address.
                if invoiceText!.lowercased().contains("lnurl") || self.isValidEmail(invoiceText!.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)) {
                    // LNURL code.
                    self.handleLNURL(code: invoiceText!.replacingOccurrences(of: "lightning:", with: "").trimmingCharacters(in: .whitespacesAndNewlines), sendVC: sendVC, receiveVC: nil)
                    
                } else if let parsedInvoice = Bindings.Bolt11Invoice.fromStr(s: invoiceText!).getValue() {
                    // Lightning invoice.
                    if let invoiceAmountMilli = parsedInvoice.amountMilliSatoshis() {
                        
                        // Calculate maximum total routing fees.
                        let maximumRoutingFeesSat = self.getLightningFeesInSatoshis(parsedInvoice: parsedInvoice, amountMsat: nil)
                        
                        // Convert invoice amount.
                        let invoiceAmount = Int(invoiceAmountMilli)/1000
                        let transactionValue = invoiceAmount.inBTC()
                        let convertedValue = String(CGFloat(Int(transactionValue*bitcoinValue.currentValue*100))/100)
                        
                        // Check if we have sufficient Lightning balance
                        let availableLightningBalance = (sendVC?.coreVC?.bittrWallet.lightningChannels.first?.outboundCapacityMsat ?? receiveVC?.coreVC?.bittrWallet.lightningChannels.first?.outboundCapacityMsat ?? 0)/1000
                        if invoiceAmount > availableLightningBalance {
                            // Check if we have sufficient onchain balance for a swap
                            self.checkAvailableOnchainBalance(invoiceAmount: invoiceAmount, availableLightningBalance: availableLightningBalance, invoiceText: invoiceText)
                            return
                        }
                        
                        // Proceed with invoice payment.
                        sendVC?.temporaryInvoiceText = invoiceText!
                        receiveVC?.temporaryInvoiceText = invoiceText!
                        sendVC?.temporaryInvoiceAmount = invoiceAmount
                        receiveVC?.temporaryInvoiceAmount = invoiceAmount
                        sendVC?.temporaryInvoiceNote = lnurlNote
                        receiveVC?.temporaryInvoiceNote = lnurlNote
                        
                        self.showAlert(
                            presentingController: self,
                            title: Language.getWord(withID: "sendtransaction"),
                            message: Language.getWord(withID: "lightningconfirmation").replacingOccurrences(of: "<amount>", with: String(invoiceAmount)).replacingOccurrences(of: "<currency>", with: bitcoinValue.chosenCurrency).replacingOccurrences(of: "<convertedamount>", with: convertedValue).replacingOccurrences(of: "<fees>", with: String(maximumRoutingFeesSat)),
                            buttons: [Language.getWord(withID: "cancel"), Language.getWord(withID: "confirm")],
                            actions: [#selector(self.cancelLightningPayment), #selector(self.performLightningPayment)])
                    } else {
                        // Zero invoice.
                        let invoiceAmount = Int(sendVC?.amountTextField.text?.toNumber() ?? 0)
                        if invoiceAmount > 0 {
                            
                            // Calculate maximum total routing fees.
                            let maximumRoutingFeesSat = self.getLightningFeesInSatoshis(parsedInvoice: parsedInvoice, amountMsat: UInt64(invoiceAmount*1000))
                            
                            // Convert invoice amount.
                            let transactionValue = invoiceAmount.inBTC()
                            let convertedValue = String(CGFloat(Int(transactionValue*bitcoinValue.currentValue*100))/100)
                            
                            // Check if we have sufficient Lightning balance.
                            let availableLightningBalance = (sendVC?.coreVC?.bittrWallet.lightningChannels.first?.outboundCapacityMsat ?? receiveVC?.coreVC?.bittrWallet.lightningChannels.first?.outboundCapacityMsat ?? 0)/1000
                            if invoiceAmount > availableLightningBalance {
                                // Insufficient Lightning balance.
                                // Check if we have sufficient onchain balance for a swap.
                                self.checkAvailableOnchainBalance(invoiceAmount: invoiceAmount, availableLightningBalance: availableLightningBalance, invoiceText: invoiceText)
                                return
                            }
                            
                            sendVC?.temporaryInvoiceText = invoiceText!
                            receiveVC?.temporaryInvoiceText = invoiceText!
                            sendVC?.temporaryInvoiceAmount = invoiceAmount
                            receiveVC?.temporaryInvoiceAmount = invoiceAmount
                            sendVC?.temporaryInvoiceNote = lnurlNote
                            receiveVC?.temporaryInvoiceNote = lnurlNote
                            sendVC?.temporaryIsZeroAmountInvoice = true
                            receiveVC?.temporaryIsZeroAmountInvoice = true
                            
                            self.showAlert(
                                presentingController: self,
                                title: Language.getWord(withID: "sendtransaction"),
                                message: Language.getWord(withID: "lightningconfirmation").replacingOccurrences(of: "<amount>", with: String(invoiceAmount)).replacingOccurrences(of: "<currency>", with: bitcoinValue.chosenCurrency).replacingOccurrences(of: "<convertedamount>", with: convertedValue).replacingOccurrences(of: "<fees>", with: String(maximumRoutingFeesSat)),
                                buttons: [Language.getWord(withID: "cancel"), Language.getWord(withID: "confirm")],
                                actions: [#selector(self.cancelLightningPayment), #selector(self.performLightningPayment)])
                        }
                    }
                }
            }
        } else {
            self.showAlert(presentingController: self, title: Language.getWord(withID: "checkyourconnection"), message: Language.getWord(withID: "trytoconnect"), buttons: [Language.getWord(withID: "okay")], actions: nil)
        }
    }
    
    func checkAvailableOnchainBalance(invoiceAmount:Int, availableLightningBalance:UInt64, invoiceText:String?) {
        
        let sendVC = self as? SendViewController
        let receiveVC = self as? ReceiveViewController
        
        let availableOnchainBalance = sendVC?.coreVC?.bittrWallet.satoshisOnchain ?? receiveVC?.homeVC?.coreVC?.bittrWallet.satoshisOnchain ?? 0
        if availableOnchainBalance >= invoiceAmount {
            // Suggest swap to Lightning
            self.showAlert(
                presentingController: self,
                title: Language.getWord(withID: "insufficientfunds"),
                message: Language.getWord(withID: "lightninginsufficientfunds").replacingOccurrences(of: "<amount>", with: String(availableLightningBalance)) + "\n\n" + Language.getWord(withID: "swapinsufficientfunds").replacingOccurrences(of: "<amount>", with: "\(availableOnchainBalance)"),
                buttons: [Language.getWord(withID: "cancel"), Language.getWord(withID: "swapandpay")],
                actions: [nil, #selector(self.swapAndPayLightning)]
            )
            // Store the invoice for the swap
            sendVC?.pendingLightningInvoice = invoiceText!
            receiveVC?.pendingLightningInvoice = invoiceText!
        } else {
            // Insufficient funds in both Lightning and onchain
            self.showAlert(presentingController: self, title: Language.getWord(withID: "insufficientfunds"), message: "\(Language.getWord(withID: "lightninginsufficientfunds")) \(availableLightningBalance) satoshis.", buttons: [Language.getWord(withID: "okay")], actions: nil)
        }
    }
    
    func getLightningFeesInSatoshis(parsedInvoice: LightningDevKit.Bolt11Invoice, amountMsat: UInt64?) -> Int {
        
        var invoicePaymentResult:Bindings.Result_C3Tuple_ThirtyTwoBytesRecipientOnionFieldsRouteParametersZNoneZ
        if amountMsat == nil {
            // Standard invoice.
            invoicePaymentResult = Bindings.paymentParametersFromInvoice(invoice: parsedInvoice)
        } else {
            // Zero amount invoice.
            invoicePaymentResult = Bindings.paymentParametersFromZeroAmountInvoice(invoice: parsedInvoice, amountMsat: amountMsat!)
        }
        let (_, _, tryRouteParams) = invoicePaymentResult.getValue()!
        let maximumRoutingFeesMsat:Int = Int(tryRouteParams.getMaxTotalRoutingFeeMsat() ?? 0)
        let maximumRoutingFeesSat:Int = maximumRoutingFeesMsat/1000
        return maximumRoutingFeesSat
    }
    
    @objc func cancelLightningPayment() {
        self.hideAlert()
        
        let sendVC = self as? SendViewController
        let receiveVC = self as? ReceiveViewController
        
        sendVC?.temporaryInvoiceText = ""
        receiveVC?.temporaryInvoiceText = ""
        sendVC?.temporaryInvoiceAmount = 0
        receiveVC?.temporaryInvoiceAmount = 0
        
        // Clear pending LNURL data when user cancels
        sendVC?.pendingLNURLCallback = nil
        sendVC?.pendingLNURLDescription = nil
        sendVC?.pendingLNURLMinAmount = nil
        sendVC?.pendingLNURLMaxAmount = nil
        
        // Clear UI fields to reset the screen
        sendVC?.toTextField.text = ""
        sendVC?.amountTextField.text = ""
        sendVC?.btcLabel.text = "Sats"
        sendVC?.selectedCurrency = .satoshis
        
        // Reset helper text to default
        if let sendVC = sendVC {
            let lightningSats = sendVC.coreVC?.bittrWallet.lightningChannels.first?.outboundCapacityMsat ?? 0
            sendVC.availableAmount.text = Language.getWord(withID:"youcansend").replacingOccurrences(of: "<amount>", with: "\(lightningSats/1000)".addSpaces())
        }
        sendVC?.temporaryInvoiceNote = nil
        receiveVC?.temporaryInvoiceNote = nil
        sendVC?.temporaryIsZeroAmountInvoice = false
        receiveVC?.temporaryIsZeroAmountInvoice = false
    }
    
    @objc func performLightningPayment() {
        self.hideAlert()
        
        let sendVC = self as? SendViewController
        let receiveVC = self as? ReceiveViewController
        
        sendVC?.nextLabel.alpha = 0
        sendVC?.arrowIcon.alpha = 0
        sendVC?.nextSpinner.startAnimating()
        
        Task {
            // Check peer connection.
            if await self.isConnectedToPeer() {
                // Is connected to peer.
                
                let invoiceText = sendVC?.temporaryInvoiceText ?? receiveVC!.temporaryInvoiceText
                sendVC?.temporaryInvoiceText = ""
                receiveVC?.temporaryInvoiceText = ""
                let invoiceAmount = sendVC?.temporaryInvoiceAmount ?? receiveVC!.temporaryInvoiceAmount
                sendVC?.temporaryInvoiceAmount = 0
                receiveVC?.temporaryInvoiceAmount = 0
                let isZeroAmountInvoice = sendVC?.temporaryIsZeroAmountInvoice ?? receiveVC!.temporaryIsZeroAmountInvoice
                sendVC?.temporaryIsZeroAmountInvoice = false
                receiveVC?.temporaryIsZeroAmountInvoice = false
                
                print("Invoice text: " + String(invoiceText.replacingOccurrences(of: " ", with: "")))
                
                do {
                    if isZeroAmountInvoice {
                        let _ = try await LightningNodeService.shared.sendZeroAmountPayment(invoice: Bolt11Invoice.fromStr(invoiceStr: String(invoiceText.replacingOccurrences(of: " ", with: ""))), amount: invoiceAmount)
                        SentrySDK.metrics.increment(key: "lightning.payment.success")
                    } else {
                        let _ = try await LightningNodeService.shared.sendPayment(invoice: Bolt11Invoice.fromStr(invoiceStr: String(invoiceText.replacingOccurrences(of: " ", with: ""))))
                        SentrySDK.metrics.increment(key: "lightning.payment.success")
                    }
                } catch {
                    let errorMessage:String = {
                        if let nodeError = error as? NodeError {
                            return "\(handleNodeError(nodeError))"
                        } else {
                            return error.localizedDescription
                        }
                    }()
                    DispatchQueue.main.async {
                        // General error alert
                        sendVC?.nextLabel.alpha = 1
                        sendVC?.arrowIcon.alpha = 1
                        sendVC?.nextSpinner.stopAnimating()
                        self.showAlert(presentingController: self, title: Language.getWord(withID: "unexpectederror"), message: errorMessage, buttons: [Language.getWord(withID: "okay")], actions: nil)
                        SentrySDK.capture(error: error) { scope in
                            scope.setExtra(value: "SendLightning row 233", key: "context")
                        }
                        SentrySDK.metrics.increment(key: "lightning.payment.failure.1")
                    }
                }
            } else {
                // Not connected to peer.
                if await LightningNodeService.shared.didEstablishPeerConnection() {
                    // Did reconnect.
                    print("Did reconnect to peer.")
                    DispatchQueue.main.async {
                        self.performLightningPayment()
                    }
                } else {
                    // Can't reconnect.
                    print("Could not reconnect to peer.")
                    DispatchQueue.main.async {
                        sendVC?.nextLabel.alpha = 1
                        sendVC?.arrowIcon.alpha = 1
                        sendVC?.nextSpinner.stopAnimating()
                        self.showAlert(presentingController: self, title: Language.getWord(withID: "bittrpeer"), message: Language.getWord(withID: "bittrpeer3"), buttons: [Language.getWord(withID: "close"), Language.getWord(withID: "connect")], actions: [nil, #selector(self.tryPeerReconnection)])
                        SentrySDK.metrics.increment(key: "lightning.payment.failure.2")
                    }
                }
            }
        }
    }
    
    @objc func tryPeerReconnection() {
        self.hideAlert()
        
        let sendVC = self as? SendViewController
        let receiveVC = self as? ReceiveViewController
        
        sendVC?.nextLabel.alpha = 0
        sendVC?.arrowIcon.alpha = 0
        sendVC?.nextSpinner.startAnimating()
        
        Task {
            if await LightningNodeService.shared.didEstablishPeerConnection() {
                // Did reconnect.
                print("Did reconnect to peer.")
                DispatchQueue.main.async {
                    self.performLightningPayment()
                }
            } else {
                // Can't reconnect.
                print("Could not reconnect to peer.")
                DispatchQueue.main.async {
                    sendVC?.nextLabel.alpha = 1
                    sendVC?.arrowIcon.alpha = 1
                    sendVC?.nextSpinner.stopAnimating()
                    self.showAlert(presentingController: self, title: Language.getWord(withID: "bittrpeer"), message: Language.getWord(withID: "bittrpeer3"), buttons: [Language.getWord(withID: "close"), Language.getWord(withID: "connect")], actions: [nil, #selector(self.tryPeerReconnection)])
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
        
        // Clear pending LNURL data when user cancels swap
        sendVC?.pendingLNURLCallback = nil
        sendVC?.pendingLNURLDescription = nil
        sendVC?.pendingLNURLMinAmount = nil
        sendVC?.pendingLNURLMaxAmount = nil
        
        // Clear UI fields to reset the screen
        sendVC?.toTextField.text = ""
        sendVC?.btcLabel.text = "Sats"
        sendVC?.selectedCurrency = .satoshis
        
        // Reset helper text to default
        if let sendVC = sendVC {
            let lightningSats = sendVC.coreVC?.bittrWallet.lightningChannels.first?.outboundCapacityMsat ?? 0
            sendVC.availableAmount.text = Language.getWord(withID:"youcansend").replacingOccurrences(of: "<amount>", with: "\(lightningSats/1000)".addSpaces())
        }
    }
    
    @objc func swapAndPayLightning() {
        self.hideAlert()
        
        let sendVC = self as? SendViewController
        let receiveVC = self as? ReceiveViewController
        
        // Navigate to swap screen with the pending invoice using existing segue pattern
        if let homeVC = sendVC?.coreVC?.homeVC ?? receiveVC?.homeVC {
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
    
    func addNewPaymentToTable(thisPayment:PaymentDetails, delegate:Any?) {
        self.hideAlert()
        
        // Set view controllers.
        let sendVC = delegate as? SendViewController
        let receiveVC = delegate as? ReceiveViewController
        let swapVC = delegate as? SwapViewController
        let coreVC = sendVC?.coreVC ?? receiveVC?.coreVC ?? swapVC?.coreVC
        
        // Update views.
        sendVC?.nextLabel.alpha = 1
        sendVC?.arrowIcon.alpha = 1
        sendVC?.nextSpinner.stopAnimating()
        sendVC?.resetFields()
        
        // Cache invoice note.
        if let temporaryInvoiceNote = (sendVC?.temporaryInvoiceNote ?? receiveVC?.temporaryInvoiceNote) {
            CacheManager.storeTransactionNote(txid: thisPayment.kind.preimageAsString ?? thisPayment.id, note: temporaryInvoiceNote)
            sendVC?.temporaryInvoiceNote = nil
            receiveVC?.temporaryInvoiceNote = nil
        }
        
        // Create transaction.
        let newTransaction = thisPayment.createTransaction(coreVC: coreVC, bittrTransactions: nil)
        CacheManager.storeLightningTransaction(thisTransaction: newTransaction)
        
        // Add invoice to Transactions table.
        sendVC?.completedTransaction = newTransaction
        receiveVC?.completedTransaction = newTransaction
        (sendVC?.coreVC?.homeVC ?? receiveVC?.coreVC?.homeVC ?? swapVC?.homeVC)?.addLightningTransaction(thisTransaction: newTransaction, paymentDetails: thisPayment)
        sendVC?.performSegue(withIdentifier: "SendToTransaction", sender: self)
        receiveVC?.performSegue(withIdentifier: "ReceiveToTransaction", sender: self)
    }
}
