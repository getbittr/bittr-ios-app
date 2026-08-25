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
        guard self.checkInternetConnection() else { return }
        
        // Recognize pending LNURL invoice if needed.
        let lnurlInvoice = self.pendingLnurlInvoice
        self.pendingLnurlInvoice = nil
        
        // Check invoice field.
        guard let enteredInvoice = lnurlInvoice ?? self.toTextField.text?.trimmingCharacters(in: .whitespacesAndNewlines), !enteredInvoice.isEmpty else {
            self.showAlert(title: Language.getWord(withID: "oops"), message: Language.getWord(withID: "enteraddress"), buttons: [.dismiss(Language.getWord(withID: "okay"))])
            return
        }
        
        // Check for LNURL
        if enteredInvoice.lowercased().isValidEmail() || enteredInvoice.lowercased().hasPrefix("lnurl") {
            self.handleLNURL(code: enteredInvoice.lowercased())
            return
        }
        
        // Show entered LNURL in ConfirmSendVC if needed.
        let typedAddress = (self.toTextField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        self.confirmLnurlEmail = (lnurlInvoice != nil && !typedAddress.isEmpty) ? typedAddress : nil
        
        // Get invoice amount.
        let satoshisAmount:Int
        let maximumRoutingFeesSat:Int
        var isBolt12Offer:Bool = false
        if let parsedInvoice = enteredInvoice.bolt11Invoice() {
            // Valid invoice.
            if let invoiceAmountMilli = parsedInvoice.amountMilliSatoshis() {
                // Normal invoice.
                satoshisAmount = Int(invoiceAmountMilli)/1000
                maximumRoutingFeesSat = self.getLightningFeesInSatoshis(parsedInvoice: parsedInvoice, amountMsat: nil)
            } else {
                // Zero invoice, needs amount.
                guard let enteredAmount = self.amountTextField.text?.trimmingCharacters(in: .whitespacesAndNewlines), !enteredAmount.isEmpty, let parsedSatoshis = self.getSatoshisFrom(enteredAmount: enteredAmount), parsedSatoshis > 0 else {
                    // No amount has been entered.
                    self.showAlert(title: Language.getWord(withID: "invoice"), message: Language.getWord(withID: "amountmissing"), buttons: [.dismiss(Language.getWord(withID: "okay"))])
                    return
                }
                satoshisAmount = parsedSatoshis
                maximumRoutingFeesSat = self.getLightningFeesInSatoshis(parsedInvoice: parsedInvoice, amountMsat: UInt64(satoshisAmount*1000))
            }
        } else if enteredInvoice.bolt12Offer() != nil {
            // BOLT12 offer. Needs amount.
            guard let enteredAmount = self.amountTextField.text?.trimmingCharacters(in: .whitespacesAndNewlines), !enteredAmount.isEmpty, let parsedSatoshis = self.getSatoshisFrom(enteredAmount: enteredAmount), parsedSatoshis > 0 else {
                // No amount has been entered.
                self.showAlert(title: Language.getWord(withID: "invoice"), message: Language.getWord(withID: "amountmissing"), buttons: [.dismiss(Language.getWord(withID: "okay"))])
                return
            }
            satoshisAmount = parsedSatoshis
            maximumRoutingFeesSat = Int((CGFloat(parsedSatoshis)/100).rounded()) + 50
            isBolt12Offer = true
        } else {
            // Invalid invoice. Ask for amount.
            self.showAlert(title: Language.getWord(withID: "oops"), message: Language.getWord(withID: "enteramount"), buttons: [.dismiss(Language.getWord(withID: "okay"))])
            return
        }
        
        // Check if we have sufficient Lightning balance.
        let availableLightningBalance = (BitcoinManager.shared.bittrWallet.lightningChannels.getActiveChannel()?.outboundCapacityMsat ?? 0)/1000
        guard satoshisAmount <= availableLightningBalance else {
            // Insufficient Lightning balance.
            if !isBolt12Offer {
                // BOLT11 invoice. Check if we have sufficient onchain balance for a swap.
                self.checkAvailableOnchainBalance(invoiceAmount: satoshisAmount, availableLightningBalance: availableLightningBalance, invoiceText: enteredInvoice)
            } else {
                // BOLT12 offer. Insufficient funds available.
                self.showAlert(title: Language.getWord(withID: "insufficientfunds"), message: Language.getWord(withID: "lightninginsufficientfunds").replacingOccurrences(of: "<amount>", with: "\(availableLightningBalance)".addSpaces()), buttons: [.dismiss(Language.getWord(withID: "okay"))])
            }
            return
        }
        
        // Set fields
        self.amountTextField.text = "\(satoshisAmount)"
        self.btcLabel.text = "Sats"
        self.selectedCurrency = .satoshis
        
        // Confirm
        self.confirmSatoshis = satoshisAmount
        self.confirmAddress = enteredInvoice
        self.confirmLightningFees = maximumRoutingFeesSat
        
        // Slide to ConfirmSendVC
        self.slideFromSendToConfirm()
    }
    
    func checkAvailableOnchainBalance(invoiceAmount:Int, availableLightningBalance:UInt64, invoiceText:String?) {
        
        let availableOnchainBalance = BitcoinManager.shared.bittrWallet.satoshisOnchain ?? 0
        if availableOnchainBalance >= invoiceAmount {
            // Suggest swap to Lightning
            self.showAlert(
                title: Language.getWord(withID: "insufficientfunds"),
                message: Language.getWord(withID: "lightninginsufficientfunds").replacingOccurrences(of: "<amount>", with: String(availableLightningBalance).addSpaces()) + "\n\n" + Language.getWord(withID: "swapinsufficientfunds").replacingOccurrences(of: "<amount>", with: "\(availableOnchainBalance)".addSpaces()),
                buttons: [.dismiss(Language.getWord(withID: "cancel")), .action(Language.getWord(withID: "swapandpay")) { self.swapAndPayLightning() }])
            // Store the invoice for the swap
            self.pendingLightningInvoice = invoiceText!
        } else {
            // Insufficient funds in both Lightning and onchain
            self.showAlert(title: Language.getWord(withID: "insufficientfunds"), message: Language.getWord(withID: "lightninginsufficientfunds").replacingOccurrences(of: "<amount>", with: "\(availableLightningBalance)".addSpaces()), buttons: [.dismiss(Language.getWord(withID: "okay"))])
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
                        self.showAlert(title: Language.getWord(withID: "bittrpeer"), message: Language.getWord(withID: "bittrpeer3"), buttons: [.dismiss(Language.getWord(withID: "close")), .action(Language.getWord(withID: "connect")) { self.performLightningPayment() }])
                        SentryManager.countMetric("lightning.payment.failure.peerUnreachable")
                    }
                }
                return
            }
            // Is connected to peer.
            
            // Get invoice and amount.
            let invoiceText = (sendVC?.confirmAddress ?? swapVC!.thisSwap!.boltzInvoice!).replacingOccurrences(of: " ", with: "")
            let invoiceAmount = sendVC?.confirmSatoshis ?? 0
            
            // Reset variables.
            sendVC?.confirmAddress = ""
            sendVC?.confirmSatoshis = 0
            
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
                    self.showAlert(title: Language.getWord(withID: "unexpectederror"), message: Language.getWord(withID: "failedinvoicepayment1").replacingOccurrences(of: "<message>", with: errorMessage), buttons: [.dismiss(Language.getWord(withID: "okay"))])
                    
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
        if let pendingLnurlNote = sendVC?.pendingLnurlNote {
            CacheManager.storeTransactionNote(txid: thisPayment.kind.transactionID ?? thisPayment.id, note: pendingLnurlNote)
            sendVC?.pendingLnurlNote = nil
        }
        
        // Create transaction.
        let newTransaction = thisPayment.createTransaction(bittrTransactions: nil)
        
        // Add invoice to Transactions table.
        sendVC?.completedTransaction = newTransaction
        receiveVC?.completedTransaction = newTransaction
        
        if newTransaction.isLightning {
            // Add lightning payment manually.
            CacheManager.storeLightningTransaction(newTransaction)
            (sendVC?.coreVC?.homeVC ?? receiveVC?.coreVC?.homeVC ?? swapVC?.homeVC)?.addLightningTransaction(thisTransaction: newTransaction, paymentDetails: thisPayment)
        } else {
            // Light sync LDK Node for onchain payments.
            BitcoinManager.shared.lightSync() { _ in }
        }
        
        // Don't auto-open the TransactionVC for a swap's own lightning payment.
        if !newTransaction.isSwap, !newTransaction.isSwapPayment {
            sendVC?.performSegue(withIdentifier: "SendToTransaction", sender: self)
            receiveVC?.performSegue(withIdentifier: "ReceiveToTransaction", sender: self)
        }
    }
}
