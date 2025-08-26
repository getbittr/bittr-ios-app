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
    
    func getNewOnchainAddress(new:Bool) -> String? {
        
        let wallet = LightningNodeService.shared.getWallet()
        if new {
            // Get a new address.
            if let address = wallet?.revealNextAddress(keychain: .external).address.description {
                return address
            } else {
                return nil
            }
        } else {
            // Get last unused address.
            if let address = wallet?.nextUnusedAddress(keychain: .external).address.description {
                return address
            } else {
                return nil
            }
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
    
    @objc func confirmOnchainAddress() {
        self.hideAlert()
        self.didDoublecheckLastUsedAddress = true
        self.getNewAddress(resetAddress: true)
    }
    
    @objc func confirmUnusedOnchainAddress() {
        self.hideAlert()
        self.getNewAddress(resetAddress: false)
    }
    
    func getNewAddress(resetAddress:Bool) {
        
        Task {
            var invoiceToDisplay:String?
            var onchainAddressToDisplay:String?
            var amountInBTC:CGFloat = 0
            let enteredDescription = (self.bothDescriptionTextField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
            
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
                } else if let newOnchainAddress = self.getNewOnchainAddress(new: false) {
                    CacheManager.storeLastAddress(newAddress: newOnchainAddress)
                    onchainAddressToDisplay = newOnchainAddress
                }
            } else {
                var new = false
                if didDoublecheckLastUsedAddress {
                    new = true
                    self.didDoublecheckLastUsedAddress = false
                }
                if let newOnchainAddress = self.getNewOnchainAddress(new: new) {
                    if self.getOnchainAddress() != nil, self.getOnchainAddress()! == newOnchainAddress {
                        // Old address is unused.
                        self.showAlert(presentingController: self, title: Language.getWord(withID: "newaddress"), message: Language.getWord(withID: "newaddress2"), buttons: [Language.getWord(withID: "cancel"), Language.getWord(withID: "confirm")], actions: [#selector(self.confirmUnusedOnchainAddress), #selector(self.confirmOnchainAddress)])
                    } else {
                        CacheManager.storeLastAddress(newAddress: newOnchainAddress)
                        onchainAddressToDisplay = newOnchainAddress
                    }
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
