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

extension SendViewController {
    
    func getSatoshisFrom(enteredAmount:String) -> Int? {
        
        switch self.selectedCurrency {
        case .satoshis:
            return enteredAmount.parsedUserAmount(allowingFraction: false)?.satoshis()
        case .bitcoin:
            return enteredAmount.parsedUserAmount()?.satoshisFromBitcoin()
        case .currency:
            let bitcoinValue = BitcoinManager.shared.bittrWallet.getCorrectBitcoinValue()
            let rate = Decimal(Double(bitcoinValue.currentValue))
            if let fiatAmount = enteredAmount.parsedUserAmount(), rate > 0 {
                return (fiatAmount / rate).satoshisFromBitcoin()
            } else {
                return nil
            }
        }
    }
    
    func checkSendLightning() {
        
        // Check invoice field.
        let enteredInvoice = (self.toTextField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if enteredInvoice.isEmpty {
            self.showAlert(presentingController: self, title: Language.getWord(withID: "oops"), message: Language.getWord(withID: "enteraddress"), buttons: [.dismiss(Language.getWord(withID: "okay"))])
            return
        }
        
        // Check amount.
        let satoshisAmount:Int
        if let parsedInvoice = Bindings.Bolt11Invoice.fromStr(s: enteredInvoice).getValue() {
            // Valid invoice.
            if let invoiceAmountMilli = parsedInvoice.amountMilliSatoshis() {
                // Normal invoice.
                satoshisAmount = Int(invoiceAmountMilli)/1000
            } else {
                // Zero invoice, needs amount.
                let enteredAmount = self.amountTextField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard !enteredAmount.isEmpty, let parsedSatoshis = self.getSatoshisFrom(enteredAmount: enteredAmount) else {
                    self.showAlert(presentingController: self, title: Language.getWord(withID: "invoice"), message: Language.getWord(withID: "amountmissing"), buttons: [.dismiss(Language.getWord(withID: "okay"))])
                    return
                }
                satoshisAmount = parsedSatoshis
            }
        } else if enteredInvoice.lowercased().isValidEmail() || enteredInvoice.lowercased().hasPrefix("lnurl") {
            // LNURL. No amount needed.
            self.handleLNURL(code: enteredInvoice.lowercased())
            return
        } else if enteredInvoice.bolt12Offer() != nil {
            // BOLT12 offer. Needs amount.
            let enteredAmount = self.amountTextField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !enteredAmount.isEmpty, let parsedSatoshis = self.getSatoshisFrom(enteredAmount: enteredAmount) else {
                self.showAlert(presentingController: self, title: Language.getWord(withID: "invoice"), message: Language.getWord(withID: "amountmissing"), buttons: [.dismiss(Language.getWord(withID: "okay"))])
                return
            }
            satoshisAmount = parsedSatoshis
        } else {
            // Invalid invoice. Ask for amount.
            self.showAlert(presentingController: self, title: Language.getWord(withID: "oops"), message: Language.getWord(withID: "enteramount"), buttons: [.dismiss(Language.getWord(withID: "okay"))])
            return
        }
        
        // Set fields
        self.amountTextField.text = "\(satoshisAmount)"
        self.btcLabel.text = "Sats"
        self.selectedCurrency = .satoshis
        
        // Confirm
        self.confirmSatoshis = satoshisAmount
        self.confirmAddress = enteredInvoice
        
        self.confirmLightningTransaction(lnurlinvoice: nil, lnurlNote: nil)
    }
    
    func confirmLightningTransaction(lnurlinvoice:String?, lnurlNote:String?) {
        guard self.checkInternetConnection() else { return }
        
        // Set LNURL invoice or manually pasted invoice.
        let invoiceText = (lnurlinvoice ?? self.toTextField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !invoiceText.isEmpty else { return }
        
        // Check for LNURL address.
        if invoiceText.lowercased().contains("lnurl") || invoiceText.lowercased().isValidEmail() {
            // LNURL code.
            self.handleLNURL(code: invoiceText.replacingOccurrences(of: "lightning:", with: ""))
            return
        }
        
        // Lightning invoice.
        let parsedInvoice = Bindings.Bolt11Invoice.fromStr(s: invoiceText).getValue()
        let bolt12Offer = invoiceText.bolt12Offer()
        guard !(parsedInvoice == nil && bolt12Offer == nil) else {
            // Invalid invoice.
            Log.info("Invalid invoice: \(invoiceText)")
            SentryManager.capture("Invalid invoice.", context: "SendLightning row 180")
            self.showAlert(presentingController: self, title: Language.getWord(withID: "oops"), message: Language.getWord(withID: "invalidinvoice2").replacingOccurrences(of: "<invoice>", with: invoiceText), buttons: [.dismiss(Language.getWord(withID: "okay"))])
            return
        }
        
        // Get invoice amount and routing fees.
        let maximumRoutingFeesSat:Int
        let invoiceAmount:Int
        
        if parsedInvoice != nil {
            if let invoiceAmountMilli = parsedInvoice!.amountMilliSatoshis() {
                // Regular invoice.
                invoiceAmount = Int(invoiceAmountMilli)/1000
                
                // Calculate maximum total routing fees.
                maximumRoutingFeesSat = self.getLightningFeesInSatoshis(parsedInvoice: parsedInvoice!, amountMsat: nil)
            } else {
                // Zero invoice.
                invoiceAmount = self.amountTextField.text?.parsedUserAmount(allowingFraction: false)?.satoshis() ?? 0
                
                if invoiceAmount > 0 {
                    // Calculate maximum total routing fees.
                    maximumRoutingFeesSat = self.getLightningFeesInSatoshis(parsedInvoice: parsedInvoice!, amountMsat: UInt64(invoiceAmount*1000))
                } else {
                    return
                }
            }
        } else {
            // BOLT12 offer.
            invoiceAmount = self.amountTextField.text?.parsedUserAmount(allowingFraction: false)?.satoshis() ?? 0
            maximumRoutingFeesSat = Int((CGFloat(invoiceAmount)/100).rounded()) + 50
        }
        
        // Check if we have sufficient Lightning balance.
        let availableLightningBalance = (BitcoinManager.shared.bittrWallet.lightningChannels.getActiveChannel()?.outboundCapacityMsat ?? 0)/1000
        if invoiceAmount > availableLightningBalance {
            // Insufficient Lightning balance.
            if bolt12Offer == nil {
                // BOLT11 invoice. Check if we have sufficient onchain balance for a swap.
                self.checkAvailableOnchainBalance(invoiceAmount: invoiceAmount, availableLightningBalance: availableLightningBalance, invoiceText: invoiceText)
            } else {
                // BOLT12 offer. Insufficient funds available.
                self.showAlert(presentingController: self, title: Language.getWord(withID: "insufficientfunds"), message: Language.getWord(withID: "lightninginsufficientfunds").replacingOccurrences(of: "<amount>", with: "\(availableLightningBalance)".addSpaces()), buttons: [.dismiss(Language.getWord(withID: "okay"))])
            }
            return
        }
        
        // Set LNURL values.
        if lnurlinvoice != nil {
            self.confirmAddress = self.toTextField.text ?? invoiceText
            self.confirmSatoshis = invoiceAmount
        }
        
        // Proceed with invoice payment.
        self.temporaryInvoiceText = invoiceText
        self.temporaryInvoiceAmount = invoiceAmount
        self.temporaryInvoiceNote = lnurlNote
        
        // Confirm details.
        self.confirmLightningFees = maximumRoutingFeesSat
        self.slideFromSendToConfirm()
    }
    
    func checkAvailableOnchainBalance(invoiceAmount:Int, availableLightningBalance:UInt64, invoiceText:String?) {
        
        let availableOnchainBalance = BitcoinManager.shared.bittrWallet.satoshisOnchain ?? 0
        if availableOnchainBalance >= invoiceAmount {
            // Suggest swap to Lightning
            self.showAlert(
                presentingController: self,
                title: Language.getWord(withID: "insufficientfunds"),
                message: Language.getWord(withID: "lightninginsufficientfunds").replacingOccurrences(of: "<amount>", with: String(availableLightningBalance).addSpaces()) + "\n\n" + Language.getWord(withID: "swapinsufficientfunds").replacingOccurrences(of: "<amount>", with: "\(availableOnchainBalance)".addSpaces()),
                buttons: [.dismiss(Language.getWord(withID: "cancel")), .action(Language.getWord(withID: "swapandpay")) { self.swapAndPayLightning() }])
            // Store the invoice for the swap
            self.pendingLightningInvoice = invoiceText!
        } else {
            // Insufficient funds in both Lightning and onchain
            self.showAlert(presentingController: self, title: Language.getWord(withID: "insufficientfunds"), message: Language.getWord(withID: "lightninginsufficientfunds").replacingOccurrences(of: "<amount>", with: "\(availableLightningBalance)".addSpaces()), buttons: [.dismiss(Language.getWord(withID: "okay"))])
        }
    }
    
}

extension UIViewController {
    
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
    
    func performLightningPayment() {
        
        let confirmSendVC = self as? ConfirmSendViewController
        let sendVC = (self as? SendViewController) ?? confirmSendVC?.sendVC
        let swapVC = self as? SwapViewController
        
        sendVC?.nextLabel.alpha = 0
        sendVC?.arrowIcon.alpha = 0
        sendVC?.nextSpinner.startAnimating()
        
        confirmSendVC?.confirmLabel.alpha = 0
        confirmSendVC?.confirmSpinner.startAnimating()
        
        Task {
            // Check peer connection.
            guard isConnectedToPeer() else {
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
                        confirmSendVC?.confirmLabel.alpha = 1
                        confirmSendVC?.confirmSpinner.stopAnimating()
                        self.showAlert(presentingController: self, title: Language.getWord(withID: "bittrpeer"), message: Language.getWord(withID: "bittrpeer3"), buttons: [.dismiss(Language.getWord(withID: "close")), .action(Language.getWord(withID: "connect")) { self.performLightningPayment() }])
                        SentryManager.countMetric("lightning.payment.failure.peerUnreachable")
                    }
                }
                return
            }
            // Is connected to peer.
            
            // Get invoice and amount.
            let invoiceText = (sendVC?.temporaryInvoiceText ?? swapVC!.thisSwap!.boltzInvoice!).replacingOccurrences(of: " ", with: "")
            let invoiceAmount = sendVC?.temporaryInvoiceAmount ?? 0
            
            // Reset variables.
            sendVC?.temporaryInvoiceText = ""
            sendVC?.temporaryInvoiceAmount = 0
            
            Log.debug("Invoice text: " + String(invoiceText))
            
            do {
                if let bolt12Offer = invoiceText.bolt12Offer() {
                    Log.info("Perform BOLT12 payment.")
                    let _ = try BitcoinManager.shared.sendBolt12Payment(offer: bolt12Offer, amount: invoiceAmount)
                } else {
                    Log.info("Perform BOLT11 payment.")
                    let invoice = try Bolt11Invoice.fromStr(invoiceStr: invoiceText)
                    
                    // Check invoice type.
                    if invoice.amountMilliSatoshis() == nil {
                        Log.info("Perform sendZeroAmountPayment.")
                        let _ = try BitcoinManager.shared.sendZeroAmountPayment(invoice: invoice, amount: invoiceAmount)
                    } else {
                        Log.info("Perform sendPayment.")
                        let paymentHash = try BitcoinManager.shared.sendPayment(invoice: invoice)
                        if swapVC?.swapStatusVC != nil {
                            SwapManager.didReceivePaymentHash(paymentHash, swapVC: swapVC!.swapStatusVC!)
                        }
                    }
                }
            } catch {
                Log.info("LDKnode is running: \(BitcoinManager.shared.status()?.isRunning ?? false)")
                Log.info("Peer is connected: \(isConnectedToPeer())")
                Log.info("Channel isUsable: \(BitcoinManager.shared.listChannels().getActiveChannel()?.isUsable ?? false)")
                Log.info("Channel isChannelReady: \(BitcoinManager.shared.listChannels().getActiveChannel()?.isChannelReady ?? false)")
                let errorMessage:String = {
                    if let nodeError = error as? NodeError {
                        return "\(handleNodeError(nodeError).detail)"
                    } else {
                        return error.localizedDescription
                    }
                }()
                DispatchQueue.main.async {
                    // Clear UI.
                    sendVC?.nextLabel.alpha = 1
                    sendVC?.arrowIcon.alpha = 1
                    sendVC?.nextSpinner.stopAnimating()
                    confirmSendVC?.confirmLabel.alpha = 1
                    confirmSendVC?.confirmSpinner.stopAnimating()
                    
                    // Show alert.
                    self.showAlert(presentingController: sendVC ?? self, title: Language.getWord(withID: "unexpectederror"), message: Language.getWord(withID: "failedinvoicepayment1").replacingOccurrences(of: "<message>", with: errorMessage), buttons: [.dismiss(Language.getWord(withID: "okay"))])
                    
                    // Slide back from ConfirmSendVC to SendVC.
                    sendVC?.slideFromConfirmToSend()
                    
                    // Count Sentry metrics.
                    if swapVC != nil {
                        SentryManager.countMetric("swap.lightningtoonchain.failed")
                    }
                    if invoiceText.bolt12Offer() != nil {
                        SentryManager.countMetric("lightning.bolt12payment.failure.\(error.paymentFailureReason)")
                    } else {
                        SentryManager.countMetric("lightning.payment.failure.\(error.paymentFailureReason)")
                    }
                    
                    // Capture Sentry error.
                    SentryManager.capture(error, context: "SendLightning row 233")
                }
            }
        }
    }
    
    func swapAndPayLightning() {
        
        let sendVC = self as? SendViewController
        
        // Navigate to swap screen with the pending invoice using existing segue pattern
        if let coreVC = sendVC?.coreVC {
            // Store the pending invoice in a way that can be accessed by the swap screen
            let pendingInvoice = sendVC?.pendingLightningInvoice ?? ""
            
            // First dismiss the current view controller
            self.dismiss(animated: true) {
                // Then navigate through the existing segue pattern
                coreVC.isFromLightningPayment = true
                coreVC.pendingLightningInvoice = pendingInvoice
                coreVC.performSegue(withIdentifier: "CoreToSwap", sender: coreVC)
            }
        }
    }
    
    func addNewPaymentToTable(thisPayment:PaymentDetails) {
        
        // Set view controllers.
        let sendVC = self as? SendViewController
        let receiveVC = self as? ReceiveViewController
        let swapVC = self as? SwapViewController
        let coreVC = sendVC?.coreVC ?? receiveVC?.coreVC ?? swapVC?.coreVC
        
        // Update views.
        sendVC?.nextLabel.alpha = 1
        sendVC?.arrowIcon.alpha = 1
        sendVC?.nextSpinner.stopAnimating()
        sendVC?.confirmSendVC?.confirmLabel.alpha = 1
        sendVC?.confirmSendVC?.confirmSpinner.stopAnimating()
        sendVC?.resetFields()
        sendVC?.slideFromConfirmToSend()
        
        // Cache invoice note.
        if let temporaryInvoiceNote = sendVC?.temporaryInvoiceNote {
            CacheManager.storeTransactionNote(txid: thisPayment.kind.transactionID ?? thisPayment.id, note: temporaryInvoiceNote)
            sendVC?.temporaryInvoiceNote = nil
        }
        
        // Create transaction.
        let newTransaction = thisPayment.createTransaction(bittrTransactions: nil)
        CacheManager.storeLightningTransaction(newTransaction)
        
        // Add invoice to Transactions table.
        sendVC?.completedTransaction = newTransaction
        receiveVC?.completedTransaction = newTransaction
        (sendVC?.coreVC?.homeVC ?? receiveVC?.coreVC?.homeVC ?? swapVC?.homeVC)?.addLightningTransaction(thisTransaction: newTransaction, paymentDetails: thisPayment)

        // Don't auto-open the TransactionVC for a swap's own lightning payment.
        if !newTransaction.isSwap, !newTransaction.isSwapPayment {
            sendVC?.performSegue(withIdentifier: "SendToTransaction", sender: self)
            receiveVC?.performSegue(withIdentifier: "ReceiveToTransaction", sender: self)
        }
    }
}
