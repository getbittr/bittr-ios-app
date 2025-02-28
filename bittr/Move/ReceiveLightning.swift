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
    
    func receivePayment(amountMsat: UInt64, description: String, expirySecs: UInt32) {
        Task {
            do {
                let invoice = try await LightningNodeService.shared.receivePayment(
                    amountMsat: amountMsat,
                    description: description,
                    expirySecs: expirySecs
                )
                DispatchQueue.main.async {
                    
                    let invoiceHash = self.getInvoiceHash(invoiceString: invoice)
                    let newTimestamp = Int(Date().timeIntervalSince1970)
                    if let actualInvoiceHash = invoiceHash {
                        CacheManager.storeInvoiceTimestamp(hash: actualInvoiceHash, timestamp: newTimestamp)
                        if let actualInvoiceText = self.descriptionTextField.text {
                            CacheManager.storeInvoiceDescription(hash: actualInvoiceHash, desc: actualInvoiceText)
                        }
                    }
                    
                    self.lnInvoiceLabel.text = "\(invoice)"
                    self.lnQRImage.image = self.generateQRCode(from: "lightning:" + invoice)
                    self.lnQRImage.layer.magnificationFilter = .nearest
                    self.lnQRCodeLogoView.alpha = 1
                    self.createdInvoice = invoice
                    
                    // Show confirmation view.
                    UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseInOut) {
                        NSLayoutConstraint.deactivate([self.scrollViewTrailing])
                        self.scrollViewTrailing = NSLayoutConstraint(item: self.scrollView, attribute: .trailing, relatedBy: .equal, toItem: self.view, attribute: .leading, multiplier: 1, constant: 0)
                        NSLayoutConstraint.activate([self.scrollViewTrailing])
                        self.view.layoutIfNeeded()
                    }
                    
                    self.amountTextField.text = nil
                    self.descriptionTextField.text = nil
                }
            } catch let error as NodeError {
                let errorString = handleNodeError(error)
                DispatchQueue.main.async {
                    self.showAlert(title: Language.getWord(withID: "error"), message: errorString.detail, buttons: [Language.getWord(withID: "okay")], actions: nil)
                    SentrySDK.capture(error: error)
                }
            } catch {
                DispatchQueue.main.async {
                    self.showAlert(title: Language.getWord(withID: "unexpectederror"), message: error.localizedDescription, buttons: [Language.getWord(withID: "okay")], actions: nil)
                    SentrySDK.capture(error: error)
                }
            }
        }
    }
    
}
