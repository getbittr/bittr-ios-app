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
import LDKNodeFFI
import LightningDevKit
import Sentry
import BitcoinDevKit

extension ReceiveViewController {
    
    func getZeroInvoice(enteredDescription:String) async -> String? {
        do {
            let invoiceDescription = Bolt11InvoiceDescription.direct(description: enteredDescription)
            let zeroInvoice = try LightningNodeService.shared.ldkNode!.bolt11Payment().receiveVariableAmount(description: invoiceDescription, expirySecs: 3600)
            
            DispatchQueue.main.async {
                if let invoiceHash = self.getInvoiceHash(invoiceString: zeroInvoice.description), let paymentDetails = LightningNodeService.shared.getPaymentDetails(paymentHash: invoiceHash) {
                    let newTimestamp = Int(Date().timeIntervalSince1970)
                    CacheManager.storeInvoiceTimestamp(preimage: paymentDetails.kind.preimageAsString ?? paymentDetails.id, timestamp: newTimestamp)
                    if enteredDescription != "" {
                        CacheManager.storeInvoiceDescription(preimage: paymentDetails.kind.preimageAsString ?? paymentDetails.id, desc: enteredDescription)
                    }
                }
            }
            return zeroInvoice.description
        } catch {
            let errorMessage:String = {
                if let nodeError = error as? NodeError {
                    return "\(handleNodeError(nodeError))"
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
    }
    
    func getRegularInvoice(amountMsat: UInt64, description: String, expirySecs: UInt32) async -> String? {
        
        do {
            let invoice = try await LightningNodeService.shared.receivePayment(
                amountMsat: amountMsat,
                description: description,
                expirySecs: expirySecs
            )
            DispatchQueue.main.async {
                if let invoiceHash = self.getInvoiceHash(invoiceString: invoice.description), let paymentDetails = LightningNodeService.shared.getPaymentDetails(paymentHash: invoiceHash) {
                    CacheManager.storeInvoiceTimestamp(preimage: paymentDetails.kind.preimageAsString ?? paymentDetails.id, timestamp: Int(Date().timeIntervalSince1970))
                }
            }
            return "\(invoice)"
        } catch {
            let errorMessage:String = {
                if let nodeError = error as? NodeError {
                    return "\(handleNodeError(nodeError))"
                } else {
                    return error.localizedDescription
                }
            }()
            DispatchQueue.main.async {
                self.showAlert(presentingController: self, title: Language.getWord(withID: "unexpectederror"), message: errorMessage, buttons: [Language.getWord(withID: "okay")], actions: nil)
                SentrySDK.capture(error: error) { scope in
                    scope.setExtra(value: "ReceiveLightning row 77", key: "context")
                }
            }
            return nil
        }
    }
    
}
