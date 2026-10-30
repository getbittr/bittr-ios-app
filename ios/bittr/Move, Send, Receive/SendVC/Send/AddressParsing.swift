//
//  AddressParsing.swift
//  bittr
//
//  Created by Tom Melters on 02/07/2024.
//

import UIKit
import BitcoinDevKit
import LNURLDecoder
import LDKNode

extension SendViewController {
    
    func handleScannedOrPastedString(_ code:String) {
        Log.debug("Code: " + code)
        
        // A new code replaces any LNURL that was still pending.
        self.clearPendingLnurlState()
        
        // Parse code components.
        let paymentCode = code.parsedPaymentCode()
        let bitcoinAddress = paymentCode.bitcoinAddress
        let lightningInvoice = paymentCode.lightningInvoice
        let lnurl = paymentCode.lnurl
        let amount = paymentCode.amountSats
        
        // Check and handle parsed code components.
        if lnurl != nil {
            Log.info("Did find LNURL.")
            
            self.toTextField.text = lnurl!
            self.handleLNURL(code: lnurl!)
            self.onchainOrLightning = .lightning
        } else if lightningInvoice != nil {
            Log.info("Did find invoice.")
            
            self.toTextField.text = lightningInvoice!
            self.onchainOrLightning = .lightning
            
            // Display the invoice amount if it carries one.
            if let invoiceAmountMilli = lightningInvoice!.bolt11Invoice()?.amountMilliSatoshis() {
                // Regular invoice
                let invoiceAmount = Int(invoiceAmountMilli)/1000
                
                let availableLightningBalance = (BitcoinManager.shared.bittrWallet.lightningChannels.getActiveChannel()?.outboundCapacityMsat ?? 0)/1000
                if invoiceAmount > availableLightningBalance, bitcoinAddress != nil {
                    // We can't send this much in Lightning, but the unified QR
                    // carries an onchain address. Send onchain instead.
                    self.handleScannedOrPastedString(bitcoinAddress!)
                    return
                }
                
                // Show the parsed amount regardless of channel capacity. If it
                // exceeds the lightning balance (e.g. no channel), the swap
                // suggestion on Next handles the insufficient-balance case.
                self.amountTextField.text = "\(invoiceAmount)"
                self.btcLabel.text = "Sats"
                self.selectedCurrency = .satoshis
            }
            
            if bitcoinAddress != nil {
                Log.info("Did also find onchain address.")
                self.bitcoinQR = bitcoinAddress!
            }
        } else if bitcoinAddress != nil {
            Log.info("Did find onchain address.")
            self.toTextField.text = bitcoinAddress!
            self.onchainOrLightning = .onchain
            if let amount, amount != 0 {
                self.amountTextField.text = "\(amount)"
                self.btcLabel.text = "Sats"
                self.selectedCurrency = .satoshis
            }
        } else {
            Log.info("Did not find a valid address or invoice.")
            self.toTextField.text = nil
            self.amountTextField.text = nil
            self.showAlert(title: Language.getWord(withID: "nobitcoinaddressfound"), message: Language.getWord(withID: "pleasescan"), buttons: [.dismiss(Language.getWord(withID: "okay"))])
            return
        }
        
        // Update labels.
        self.updateLabels()
    }
}

// What a scanned, pasted or typed code can pay to.
struct PaymentCode {
    var bitcoinAddress:String?
    var lightningInvoice:String?
    var lnurl:String?
    var amountSats:Int?
}

extension String {
    
    func parsedPaymentCode() -> PaymentCode {
        var paymentCode = PaymentCode()
        let code = self.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if code.lowercased().hasPrefix("bitcoin:") {
            // A BIP21 link: the address is its path, and only the amount and lightning parameters are read.
            guard let components = URLComponents(string: code) else { return paymentCode }
            
            // Extract bitcoin address.
            // A "bitcoin://" link puts the address in the host instead.
            let address = components.path.isEmpty ? (components.host ?? "") : components.path
            paymentCode.bitcoinAddress = address.asBitcoinAddress()
            
            // Extract lightning invoice and amount.
            for item in components.queryItems ?? [] {
                guard let value = item.value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { continue }
                switch item.name.lowercased() {
                case "amount":
                    paymentCode.amountSats = value.parsedNumber()?.satoshisFromBitcoin()
                case "lightning":
                    let lightning = value.lowercased()
                    if lightning.isValidInvoice() {
                        paymentCode.lightningInvoice = lightning
                    } else if lightning.hasPrefix("lnurl") {
                        paymentCode.lnurl = lightning
                    }
                default: break
                }
            }
            return paymentCode
        }
        
        // Anything else is one code on its own.
        var single = code.lowercased()
        if single.hasPrefix("lightning:") {
            single = String(single.dropFirst("lightning:".count))
        }
        if single.isValidInvoice() {
            paymentCode.lightningInvoice = single
        } else if single.isValidEmail() || single.hasPrefix("lnurl") {
            paymentCode.lnurl = single
        } else {
            paymentCode.bitcoinAddress = code.asBitcoinAddress()
        }
        return paymentCode
    }
    
    func asBitcoinAddress() -> String? {
        // Verify non-lowercased address first.
        if self.isValidBitcoinAddress() { return self }
        
        // If invalid, then verify lowercased address.
        guard self.rangeOfCharacter(from: .lowercaseLetters) == nil else { return nil }
        return self.lowercased().isValidBitcoinAddress() ? self.lowercased() : nil
    }
    
    func isValidBitcoinAddress() -> Bool {
        (try? BitcoinDevKit.Address(address: self, network: EnvironmentConfig.bitcoinDevKitNetwork)) != nil
    }
    
    func isValidInvoice() -> Bool {
        guard self.hasPrefix("ln") else { return false }
        if self.bolt11Invoice() != nil {
            return true
        } else {
            if let _ = self.bolt12Offer() {
                return true
            } else {
                return false
            }
        }
    }
}
