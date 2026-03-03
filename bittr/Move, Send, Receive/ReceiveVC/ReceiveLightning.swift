//
//  ReceiveLightning.swift
//  bittr
//
//  Created by Tom Melters on 14/07/2024.
//

import UIKit
import CoreImage.CIFilterBuiltins
import CodeScanner
import LDKNode
import Sentry

extension ReceiveViewController {
    
    func getZeroInvoice(enteredDescription:String) async -> String? {
        
        let invoiceDescription = Bolt11InvoiceDescription.direct(description: enteredDescription)
        let zeroInvoice:Bolt11Invoice
        do {
            zeroInvoice = try BitcoinManager.shared.ldkNode!.bolt11Payment().receiveVariableAmount(description: invoiceDescription, expirySecs: 3600)
        } catch {
            let errorMessage:String = {
                if let nodeError = error as? NodeError {
                    return "\(handleNodeError(nodeError).detail)"
                } else {
                    return error.localizedDescription
                }
            }()
            DispatchQueue.main.async {
                self.showAlert(presentingController: self, title: Language.getWord(withID: "unexpectederror"), message: errorMessage, buttons: [Language.getWord(withID: "okay")], actions: nil)
                SentrySDK.capture(error: error) { scope in
                    scope.setExtra(value: "ReceiveLightning row 45", key: "context")
                }
            }
            return nil
        }
            
        DispatchQueue.main.async {
            if let invoiceHash = zeroInvoice.description.getInvoiceHash(), let paymentDetails = BitcoinManager.shared.getPaymentDetails(paymentHash: invoiceHash) {
                let newTimestamp = Int(Date().timeIntervalSince1970)
                CacheManager.storeInvoiceTimestamp(preimage: paymentDetails.kind.transactionID ?? paymentDetails.id, timestamp: newTimestamp)
                if enteredDescription != "" {
                    CacheManager.storeInvoiceDescription(preimage: paymentDetails.kind.transactionID ?? paymentDetails.id, desc: enteredDescription)
                }
            }
        }
        
        return zeroInvoice.description
    }
    
    func getRegularInvoice(amountMsat: UInt64, description: String, expirySecs: UInt32) async -> String? {
        
        guard let invoice = await BitcoinManager.shared.getInvoice(
            amountMsat: amountMsat,
            description: description,
            expirySecs: expirySecs)
        else {
            DispatchQueue.main.async {
                self.showAlert(presentingController: self, title: Language.getWord(withID: "unexpectederror"), message: Language.getWord(withID: "invoicecreatefail"), buttons: [Language.getWord(withID: "okay")], actions: nil)
            }
            return nil
        }
        
        DispatchQueue.main.async {
            if let invoiceHash = invoice.description.getInvoiceHash(), let paymentDetails = BitcoinManager.shared.getPaymentDetails(paymentHash: invoiceHash) {
                CacheManager.storeInvoiceTimestamp(preimage: paymentDetails.kind.transactionID ?? paymentDetails.id, timestamp: Int(Date().timeIntervalSince1970))
            }
        }
        return "\(invoice)"
    }
    
}
