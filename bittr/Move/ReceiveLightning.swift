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
                let invoiceHash = self.getInvoiceHash(invoiceString: zeroInvoice.description)
                let newTimestamp = Int(Date().timeIntervalSince1970)
                if let actualInvoiceHash = invoiceHash {
                    CacheManager.storeInvoiceTimestamp(hash: actualInvoiceHash, timestamp: newTimestamp)
                    if enteredDescription != "" {
                        CacheManager.storeInvoiceDescription(hash: actualInvoiceHash, desc: enteredDescription)
                    }
                }
            }
            return zeroInvoice.description
        } catch let error as NodeError {
            let errorString = handleNodeError(error)
            DispatchQueue.main.async {
                self.showAlert(presentingController: self, title: Language.getWord(withID: "error"), message: errorString.detail, buttons: [Language.getWord(withID: "okay")], actions: nil)
                SentrySDK.capture(error: error)
            }
            return nil
        } catch {
            DispatchQueue.main.async {
                self.showAlert(presentingController: self, title: Language.getWord(withID: "unexpectederror"), message: error.localizedDescription, buttons: [Language.getWord(withID: "okay")], actions: nil)
                SentrySDK.capture(error: error)
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
                let invoiceHash = self.getInvoiceHash(invoiceString: invoice.description)
                let newTimestamp = Int(Date().timeIntervalSince1970)
                if let actualInvoiceHash = invoiceHash {
                    CacheManager.storeInvoiceTimestamp(hash: actualInvoiceHash, timestamp: newTimestamp)
                }
            }
            return "\(invoice)"
        } catch let error as NodeError {
            let errorString = handleNodeError(error)
            DispatchQueue.main.async {
                self.showAlert(presentingController: self, title: Language.getWord(withID: "error"), message: errorString.detail, buttons: [Language.getWord(withID: "okay")], actions: nil)
                SentrySDK.capture(error: error)
            }
            return nil
        } catch {
            DispatchQueue.main.async {
                self.showAlert(presentingController: self, title: Language.getWord(withID: "unexpectederror"), message: error.localizedDescription, buttons: [Language.getWord(withID: "okay")], actions: nil)
                SentrySDK.capture(error: error)
            }
            return nil
        }
    }
    
}
