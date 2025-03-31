//
//  ReceiveOnchain.swift
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
    
    func getNewOnchainAddress() -> String? {
        
        do {
            let wallet = LightningNodeService.shared.getWallet()
            if let address = try wallet?.getAddress(addressIndex: .new).address.asString() {
                DispatchQueue.main.async {
                    CacheManager.storeLastAddress(newAddress: address)
                }
                return address
            } else {
                /*DispatchQueue.main.async {
                    let alert = UIAlertController(title: Language.getWord(withID: "oops"), message: Language.getWord(withID: "addressfail"), preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: Language.getWord(withID: "tryagain"), style: .cancel, handler: {_ in
                        self.getNewAddress(resetAddress: true)
                    }))
                    alert.addAction(UIAlertAction(title: Language.getWord(withID: "cancel"), style: .cancel, handler: {_ in
                        self.addressSpinner.stopAnimating()
                        self.qrCodeSpinner.stopAnimating()
                        self.bothQrCodeSpinner.stopAnimating()
                    }))
                    self.present(alert, animated: true)
                }*/
                return nil
            }
        } catch let error as NodeError {
            let errorString = handleNodeError(error)
            DispatchQueue.main.async {
                /*let alert = UIAlertController(title: Language.getWord(withID: "oops"), message: "\(Language.getWord(withID: "addressfail2")). (\(errorString).) \(Language.getWord(withID: "pleasetryagain")).", preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: Language.getWord(withID: "tryagain"), style: .cancel, handler: {_ in
                    self.getNewAddress(resetAddress: true)
                }))
                alert.addAction(UIAlertAction(title: Language.getWord(withID: "cancel"), style: .cancel, handler: {_ in
                    self.addressSpinner.stopAnimating()
                    self.qrCodeSpinner.stopAnimating()
                    self.bothQrCodeSpinner.stopAnimating()
                }))
                self.present(alert, animated: true)*/
                
                SentrySDK.capture(error: error)
            }
            return nil
        } catch {
            DispatchQueue.main.async {
                /*let alert = UIAlertController(title: Language.getWord(withID: "oops"), message: Language.getWord(withID: "addressfail"), preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: Language.getWord(withID: "tryagain"), style: .cancel, handler: {_ in
                    self.getNewAddress(resetAddress: true)
                }))
                alert.addAction(UIAlertAction(title: Language.getWord(withID: "cancel"), style: .cancel, handler: {_ in
                    self.addressSpinner.stopAnimating()
                    self.qrCodeSpinner.stopAnimating()
                    self.bothQrCodeSpinner.stopAnimating()
                }))
                self.present(alert, animated: true)*/
                
                SentrySDK.capture(error: error)
            }
            return nil
        }
    }
    
    func getOnchainAddress() -> String? {
        
        if let cachedAddress = CacheManager.getLastAddress() {
            print("Show cached address.")
            return cachedAddress
        } else {
            print("Show new address.")
            return nil
        }
    }
    
    func getNewAddress(resetAddress:Bool) {
        
        Task {
            var invoiceToDisplay:String?
            var onchainAddressToDisplay:String?
            var amountInBTC:CGFloat = 0
            var enteredDescription = (self.bothDescriptionTextField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
            
            if self.bothAmountTextField.text != nil, self.bothAmountTextField.text!.trimmingCharacters(in: .whitespacesAndNewlines) != "" {
                // An amount has been entered. Create a regular invoice.
                amountInBTC = CGFloat(Int(self.bothAmountTextField.text!.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0)/100000000
                let amountInMsat = (Int(self.bothAmountTextField.text!.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0)*1000
                invoiceToDisplay = await self.getRegularInvoice(amountMsat: UInt64(amountInMsat), description: enteredDescription, expirySecs: 3600)
            } else {
                // No amount has been entered. Create a zero invoice.
                invoiceToDisplay = await self.getZeroInvoice(enteredDescription: enteredDescription)
            }
                
            if !resetAddress {
                if let cachedOnchainAddress = self.getOnchainAddress() {
                    onchainAddressToDisplay = cachedOnchainAddress
                } else if let newOnchainAddress = self.getNewOnchainAddress() {
                    onchainAddressToDisplay = newOnchainAddress
                }
            } else {
                if let newOnchainAddress = self.getNewOnchainAddress() {
                    onchainAddressToDisplay = newOnchainAddress
                }
            }
            
            if onchainAddressToDisplay != nil, invoiceToDisplay != nil {
                
                DispatchQueue.main.async {
                    // Address labels
                    self.addressLabel.text = onchainAddressToDisplay!
                    self.lnInvoiceLabel.text = invoiceToDisplay!
                    var amountText = ""
                    var labelText = ""
                    if amountInBTC != 0 {
                        amountText = "?amount=\(amountInBTC)"
                    }
                    if enteredDescription != "" {
                        labelText = "&label=\(enteredDescription)"
                    }
                    self.bothAddressLabel.text = "bitcoin:\(onchainAddressToDisplay!)\(amountText)\(labelText)&lightning=\(invoiceToDisplay!)"
                    
                    // Copy images
                    self.addressCopy.alpha = 1
                    self.bothAddressCopy.alpha = 1
                    self.lnInvoiceCopy.alpha = 1
                    
                    // QR code images
                    self.qrCodeImage.image = self.generateQRCode(from: "bitcoin:\(onchainAddressToDisplay!)\(amountText)")
                    self.qrCodeImage.layer.magnificationFilter = .nearest
                    self.qrCodeImage.alpha = 1
                    self.bothQrCodeImage.image = self.generateQRCode(from: "bitcoin:\(onchainAddressToDisplay!)\(amountText)\(labelText)&lightning=\(invoiceToDisplay!)")
                    self.bothQrCodeImage.layer.magnificationFilter = .nearest
                    self.bothQrCodeImage.alpha = 1
                    self.lnQRImage.image = self.generateQRCode(from: "lightning:" + invoiceToDisplay!)
                    self.lnQRImage.layer.magnificationFilter = .nearest
                    self.lnQRImage.alpha = 1
                    
                    // Logo views
                    self.qrCodeLogoView.alpha = 1
                    self.bothQrCodeLogoView.alpha = 1
                    self.lnQRCodeLogoView.alpha = 1
                    
                    // Spinners
                    self.addressSpinner.stopAnimating()
                    self.qrCodeSpinner.stopAnimating()
                    self.bothQrCodeSpinner.stopAnimating()
                }
            }
        }
    }
    
    
}
