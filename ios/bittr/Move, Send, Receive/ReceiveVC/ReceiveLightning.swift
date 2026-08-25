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
                self.showAlert(title: Language.getWord(withID: "unexpectederror"), message: errorMessage, buttons: [.dismiss(Language.getWord(withID: "okay"))])
                SentryManager.capture(error, context: "ReceiveLightning row 45")
            }
            return nil
        }
            
        DispatchQueue.main.async {
            if let invoiceHash = zeroInvoice.description.getInvoiceHash(), let paymentDetails = BitcoinManager.shared.getPaymentDetails(paymentHash: invoiceHash) {
                let newTimestamp = Int(Date().timeIntervalSince1970)
                CacheManager.storeInvoiceTimestamp(preimage: paymentDetails.cacheID, timestamp: newTimestamp)
                if enteredDescription != "" {
                    CacheManager.storeInvoiceDescription(preimage: paymentDetails.cacheID, desc: enteredDescription)
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
                self.showAlert(title: Language.getWord(withID: "unexpectederror"), message: Language.getWord(withID: "invoicecreatefail"), buttons: [.dismiss(Language.getWord(withID: "okay"))])
            }
            return nil
        }
        
        DispatchQueue.main.async {
            if let invoiceHash = invoice.description.getInvoiceHash(), let paymentDetails = BitcoinManager.shared.getPaymentDetails(paymentHash: invoiceHash) {
                CacheManager.storeInvoiceTimestamp(preimage: paymentDetails.cacheID, timestamp: Int(Date().timeIntervalSince1970))
            }
        }
        return "\(invoice)"
    }
    
}
