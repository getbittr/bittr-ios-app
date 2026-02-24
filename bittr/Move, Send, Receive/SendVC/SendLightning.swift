//
//  SendLightning.swift
//  bittr
//
//  Created by Tom Melters on 02/07/2024.
//

import UIKit
import LDKNode
import CodeScanner
import AVFoundation
import LightningDevKit
import Sentry

extension SendViewController {
    
    func checkSendLightning() {
        
        // Check invoice field.
        let enteredInvoice = (self.toTextField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if enteredInvoice.isEmpty {
            self.showAlert(presentingController: self, title: Language.getWord(withID: "oops"), message: Language.getWord(withID: "enteraddress"), buttons: [Language.getWord(withID: "okay")], actions: nil)
            return
        }
        
        // Check amount.
        let enteredAmount = self.amountTextField.text ?? ""
        if enteredAmount.isEmpty {
            // No amount has been entered.
            if enteredInvoice.lowercased().hasPrefix("ln") {
                if let parsedInvoice = Bindings.Bolt11Invoice.fromStr(s: enteredInvoice).getValue() {
                    if let invoiceAmountMilli = parsedInvoice.amountMilliSatoshis() {
                        // Normal invoice.
                        let invoiceAmount = Int(invoiceAmountMilli)/1000
                        self.amountTextField.text = "\(invoiceAmount)"
                        self.btcLabel.text = "Sats"
                        self.selectedCurrency = .satoshis
                        self.confirmLightningTransaction(lnurlinvoice: nil, lnurlNote: nil)
                    } else {
                        // Zero invoice, needs amount.
                        self.showAlert(presentingController: self, title: Language.getWord(withID: "invoice"), message: Language.getWord(withID: "amountmissing"), buttons: [Language.getWord(withID: "okay")], actions: nil)
                    }
                } else {
                    // Invalid lightning invoice
                    self.showAlert(presentingController: self, title: Language.getWord(withID: "oops"), message: Language.getWord(withID: "enteramount"), buttons: [Language.getWord(withID: "okay")], actions: nil)
                }
            } else if enteredInvoice.lowercased().isValidEmail() {
                // LNURL. No amount needed.
                self.handleLNURL(code: enteredInvoice.lowercased(), sendVC: self, receiveVC: nil)
            } else {
                // Not a lightning invoice, amount is required
                self.showAlert(presentingController: self, title: Language.getWord(withID: "oops"), message: Language.getWord(withID: "enteramount"), buttons: [Language.getWord(withID: "okay")], actions: nil)
            }
        } else {
            // Convert amount to satoshis based on current currency.
            var satoshisValue: Int
            switch self.selectedCurrency {
            case .satoshis:
                satoshisValue = Int(enteredAmount.toNumber())
            case .bitcoin:
                let btcAmount = enteredAmount.toNumber()
                guard btcAmount.isFinite && !btcAmount.isNaN else {
                    Log.info("579 Invalid BTC amount.")
                    print("⚠️ Warning: Invalid BTC amount: \(btcAmount)")
                    return
                }
                satoshisValue = btcAmount.inSatoshis()
            case .currency:
                let fiatAmount = enteredAmount.toNumber()
                let bitcoinValue = self.getCorrectBitcoinValue(coreVC: self.coreVC!)
                let btcAmount = fiatAmount / bitcoinValue.currentValue
                
                guard btcAmount.isFinite && !btcAmount.isNaN && bitcoinValue.currentValue > 0 else {
                    Log.info("589 Invalid values.")
                    print("⚠️ Warning: Invalid values - fiatAmount: \(fiatAmount), bitcoinValue: \(bitcoinValue.currentValue), btcAmount: \(btcAmount)")
                    return
                }
                satoshisValue = btcAmount.inSatoshis()
            }
            
            self.amountTextField.text = "\(satoshisValue)"
            self.btcLabel.text = "Sats"
            self.selectedCurrency = .satoshis
            self.confirmLightningTransaction(lnurlinvoice: nil, lnurlNote: nil)
        }
    }
}

extension UIViewController {
    
    func confirmLightningTransaction(lnurlinvoice:String?, lnurlNote:String?) {
        guard self.checkInternetConnection() else { return }
        
        let sendVC = self as? SendViewController
        let receiveVC = self as? ReceiveViewController
        
        // Set LNURL invoice or manually pasted invoice.
        let invoiceText = (lnurlinvoice ?? sendVC?.toTextField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !invoiceText.isEmpty else { return }
        
        // Get current bitcoin value.
        let bitcoinValue = self.getCorrectBitcoinValue(coreVC: sendVC?.coreVC ?? receiveVC?.coreVC ?? CoreViewController())
        
        // Check for LNURL address.
        if invoiceText.lowercased().contains("lnurl") || invoiceText.lowercased().isValidEmail() {
            // LNURL code.
            self.handleLNURL(code: invoiceText.replacingOccurrences(of: "lightning:", with: ""), sendVC: sendVC, receiveVC: nil)
            
        } else if let parsedInvoice = Bindings.Bolt11Invoice.fromStr(s: invoiceText).getValue() {
            // Lightning invoice.
            
            var convertedValue = String()
            var maximumRoutingFeesSat = Int()
            var invoiceAmount = Int()
            
            if let invoiceAmountMilli = parsedInvoice.amountMilliSatoshis() {
                // Regular invoice.
                
                invoiceAmount = Int(invoiceAmountMilli)/1000
                
                // Calculate maximum total routing fees.
                maximumRoutingFeesSat = self.getLightningFeesInSatoshis(parsedInvoice: parsedInvoice, amountMsat: nil)
                
                sendVC?.temporaryIsZeroAmountInvoice = false
                receiveVC?.temporaryIsZeroAmountInvoice = false
            } else {
                // Zero invoice.
                
                invoiceAmount = Int(sendVC?.amountTextField.text?.toNumber() ?? 0)
                
                if invoiceAmount > 0 {
                    // Calculate maximum total routing fees.
                    maximumRoutingFeesSat = self.getLightningFeesInSatoshis(parsedInvoice: parsedInvoice, amountMsat: UInt64(invoiceAmount*1000))
                } else {
                    return
                }
                
                sendVC?.temporaryIsZeroAmountInvoice = true
                receiveVC?.temporaryIsZeroAmountInvoice = true
            }
            
            // Convert invoice amount.
            let transactionValue = invoiceAmount.inBTC()
            convertedValue = String(CGFloat(Int(transactionValue*bitcoinValue.currentValue*100))/100)
            
            // Check if we have sufficient Lightning balance.
            let availableLightningBalance = ((sendVC?.coreVC ?? receiveVC?.coreVC)!.bittrWallet.lightningChannels.getActiveChannel()?.outboundCapacityMsat ?? 0)/1000
            if invoiceAmount > availableLightningBalance {
                // Insufficient Lightning balance.
                // Check if we have sufficient onchain balance for a swap.
                self.checkAvailableOnchainBalance(invoiceAmount: invoiceAmount, availableLightningBalance: availableLightningBalance, invoiceText: invoiceText)
                return
            }
            
            // Proceed with invoice payment.
            sendVC?.temporaryInvoiceText = invoiceText
            receiveVC?.temporaryInvoiceText = invoiceText
            sendVC?.temporaryInvoiceAmount = invoiceAmount
            receiveVC?.temporaryInvoiceAmount = invoiceAmount
            sendVC?.temporaryInvoiceNote = lnurlNote
            receiveVC?.temporaryInvoiceNote = lnurlNote
            
            // Confirm details.
            self.showAlert(
                presentingController: self,
                title: Language.getWord(withID: "sendtransaction"),
                message: Language.getWord(withID: "lightningconfirmation")
                    .replacingOccurrences(of: "<amount>", with: String(invoiceAmount))
                    .replacingOccurrences(of: "<currency>", with: bitcoinValue.chosenCurrency)
                    .replacingOccurrences(of: "<convertedamount>", with: convertedValue)
                    .replacingOccurrences(of: "<fees>", with: String(maximumRoutingFeesSat)),
                buttons: [Language.getWord(withID: "cancel"), Language.getWord(withID: "confirm")],
                actions: [#selector(self.cancelLightningPayment), #selector(self.performLightningPayment)])
        } else {
            // Invalid invoice.
            Log.info("Invalid invoice: \(invoiceText)")
            SentrySDK.capture(message: "Invalid invoice.") { scope in
                scope.setExtra(value: "SendLightning row 180", key: "context")
            }
            self.showAlert(presentingController: self, title: Language.getWord(withID: "oops"), message: Language.getWord(withID: "invalidinvoice2").replacingOccurrences(of: "<invoice>", with: invoiceText), buttons: [Language.getWord(withID: "okay")], actions: nil)
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
            let lightningSats = sendVC.coreVC?.bittrWallet.lightningChannels.getActiveChannel()?.outboundCapacityMsat ?? 0
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
            if self.isConnectedToPeer() {
                // Is connected to peer.
                
                // Get invoice, amount, and invoice type.
                let invoiceText = (sendVC?.temporaryInvoiceText ?? receiveVC!.temporaryInvoiceText).replacingOccurrences(of: " ", with: "")
                let invoiceAmount = sendVC?.temporaryInvoiceAmount ?? receiveVC!.temporaryInvoiceAmount
                let isZeroAmountInvoice = sendVC?.temporaryIsZeroAmountInvoice ?? receiveVC!.temporaryIsZeroAmountInvoice
                
                // Reset variables.
                sendVC?.temporaryInvoiceText = ""
                receiveVC?.temporaryInvoiceText = ""
                sendVC?.temporaryInvoiceAmount = 0
                receiveVC?.temporaryInvoiceAmount = 0
                sendVC?.temporaryIsZeroAmountInvoice = false
                receiveVC?.temporaryIsZeroAmountInvoice = false
                
                print("Invoice text: " + String(invoiceText))
                
                do {
                    if isZeroAmountInvoice {
                        let _ = try await BitcoinManager.shared.sendZeroAmountPayment(invoice: Bolt11Invoice.fromStr(invoiceStr: invoiceText), amount: invoiceAmount)
                        SentrySDK.metrics.count(key: "lightning.payment.success")
                    } else {
                        let _ = try await BitcoinManager.shared.sendPayment(invoice: Bolt11Invoice.fromStr(invoiceStr: invoiceText))
                        SentrySDK.metrics.count(key: "lightning.payment.success")
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
                        SentrySDK.metrics.count(key: "lightning.payment.failure.1")
                    }
                }
            } else {
                // Not connected to peer.
                if await BitcoinManager.shared.didEstablishPeerConnection() {
                    // Did reconnect.
                    Log.info("Did reconnect to peer.")
                    DispatchQueue.main.async {
                        self.performLightningPayment()
                    }
                } else {
                    // Can't reconnect.
                    Log.info("Could not reconnect to peer.")
                    DispatchQueue.main.async {
                        sendVC?.nextLabel.alpha = 1
                        sendVC?.arrowIcon.alpha = 1
                        sendVC?.nextSpinner.stopAnimating()
                        self.showAlert(presentingController: self, title: Language.getWord(withID: "bittrpeer"), message: Language.getWord(withID: "bittrpeer3"), buttons: [Language.getWord(withID: "close"), Language.getWord(withID: "connect")], actions: [nil, #selector(self.performLightningPayment)])
                        SentrySDK.metrics.count(key: "lightning.payment.failure.2")
                    }
                }
            }
        }
    }
    
    @objc func cancelSwapOffer() {
        self.hideAlert()
        Log.info("DEBUG - cancelSwapOffer called, clearing pending data")
        
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
            let lightningSats = sendVC.coreVC?.bittrWallet.lightningChannels.getActiveChannel()?.outboundCapacityMsat ?? 0
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
                homeVC.isFromLightningPayment = true
                homeVC.pendingLightningInvoice = pendingInvoice
                homeVC.performSegue(withIdentifier: "HomeToMove", sender: homeVC)
            }
        }
    }
    
    func addNewPaymentToTable(thisPayment:PaymentDetails) {
        self.hideAlert()
        
        // Set view controllers.
        let sendVC = self as? SendViewController
        let receiveVC = self as? ReceiveViewController
        let swapVC = self as? SwapViewController
        let coreVC = sendVC?.coreVC ?? receiveVC?.coreVC ?? swapVC?.coreVC
        
        // Update views.
        sendVC?.nextLabel.alpha = 1
        sendVC?.arrowIcon.alpha = 1
        sendVC?.nextSpinner.stopAnimating()
        sendVC?.resetFields()
        
        // Cache invoice note.
        if let temporaryInvoiceNote = (sendVC?.temporaryInvoiceNote ?? receiveVC?.temporaryInvoiceNote) {
            CacheManager.storeTransactionNote(txid: thisPayment.kind.transactionID ?? thisPayment.id, note: temporaryInvoiceNote)
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
