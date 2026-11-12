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
    
    func handleScannedOrPastedString(_ code:String, fromOtherApp:Bool = false) {
        Log.debug("Code: " + code)
        
        // A new code replaces any LNURL that was still pending.
        self.clearPendingLnurlState()
        
        // Drain only for onchain addresses without amount.
        let didTapAvailable = self.didTapAvailable
        self.didTapAvailable = false
        
        // An amount the app filled in for an earlier code or tap doesn't belong to the new code, unlike one the user typed.
        let earlierAmount = self.amountTextField.text
        if let earlierAmount, !earlierAmount.isEmpty, earlierAmount == self.filledInAmount {
            self.amountTextField.text = nil
        }
        
        // Parse code components.
        let paymentCode = code.parsedPaymentCode()
        
        // A link that needs a parameter bittr doesn't understand can't be paid as it is.
        if let requirement = paymentCode.unsupportedRequirement {
            Log.info("Payment link requires an unsupported parameter: \(requirement)")
            self.toTextField.text = nil
            self.amountTextField.text = nil
            self.showAlert(title: Language.getWord(withID: "oops"), message: Language.getWord(withID: "unsupportedpaymentlink"), buttons: [.dismiss(Language.getWord(withID: "okay"))])
            return
        }
        
        // A link with a malformed or repeated parameter can't be trusted for any part of the payment.
        if paymentCode.isInvalidLink {
            Log.info("Payment link has a malformed or repeated parameter.")
            self.toTextField.text = nil
            self.amountTextField.text = nil
            self.showAlert(title: Language.getWord(withID: "oops"), message: Language.getWord(withID: "invalidpaymentlink"), buttons: [.dismiss(Language.getWord(withID: "okay"))])
            return
        }
        
        let bitcoinAddress = paymentCode.bitcoinAddress
        let lightningInvoice = paymentCode.lightningInvoice
        let lnurl = paymentCode.lnurl
        let amount = paymentCode.amountSats
        
        // Check and handle parsed code components.
        if let lnurl {
            Log.info("Did find LNURL.")
            
            self.toTextField.text = lnurl
            self.onchainOrLightning = .lightning
            
            // A link from another app only fills in the field, so no server is contacted until the user taps Next.
            if !fromOtherApp {
                self.handleLNURL(code: lnurl)
            }
        } else if let lightningInvoice {
            Log.info("Did find invoice.")
            
            self.toTextField.text = lightningInvoice
            self.onchainOrLightning = .lightning
            
            // Display the invoice amount if it carries one.
            if let invoiceAmountMilli = lightningInvoice.bolt11Invoice()?.amountMilliSatoshis() {
                // Regular invoice
                let invoiceAmount = Int(invoiceAmountMilli)/1000
                
                let availableLightningBalance = (BitcoinManager.shared.bittrWallet.lightningChannels.getActiveChannel()?.outboundCapacityMsat ?? 0)/1000
                if invoiceAmount > availableLightningBalance, let bitcoinAddress {
                    // We can't send this much in Lightning, but the unified QR
                    // carries an onchain address. Send onchain instead.
                    let bitcoinAmount = Decimal(amount ?? invoiceAmount) / Decimal(Bitcoin.satoshisPerBitcoin)
                    self.handleScannedOrPastedString("bitcoin:\(bitcoinAddress)?amount=\(bitcoinAmount)")
                    return
                }
                
                // Show the parsed amount.
                self.fillInAmount("\(invoiceAmount)")
                self.btcLabel.text = "Sats"
                self.selectedCurrency = .satoshis
            }
            
            if bitcoinAddress != nil {
                Log.info("Did also find onchain address.")
                self.bitcoinQR = bitcoinAddress!
            }
        } else if let bitcoinAddress {
            Log.info("Did find onchain address.")
            self.toTextField.text = bitcoinAddress
            self.onchainOrLightning = .onchain
            if let amount, amount != 0 {
                self.fillInAmount("\(amount)")
                self.btcLabel.text = "Sats"
                self.selectedCurrency = .satoshis
            } else {
                self.didTapAvailable = didTapAvailable
                if didTapAvailable { self.amountTextField.text = earlierAmount }
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
    var unsupportedRequirement:String?
    var isInvalidLink = false
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
            var readParameters = Set<String>()
            for item in components.queryItems ?? [] {
                // BIP21 makes the whole link invalid when it has a req- parameter the wallet doesn't understand, and bittr understands none.
                if item.name.lowercased().hasPrefix("req-") {
                    return PaymentCode(unsupportedRequirement: item.name)
                }
                guard let value = item.value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { continue }
                
                // A link that gives its amount or lightning code twice is ambiguous.
                let name = item.name.lowercased()
                if name == "amount" || name == "lightning" {
                    guard readParameters.insert(name).inserted else { return PaymentCode(isInvalidLink: true) }
                }
                
                switch name {
                case "amount":
                    guard let amountSats = value.bip21Satoshis() else { return PaymentCode(isInvalidLink: true) }
                    paymentCode.amountSats = amountSats
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
    
    // A BIP21 amount is bitcoin in ASCII digits with an optional "." and at most 8 decimals.
    func bip21Satoshis() -> Int? {
        let parts = self.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        let whole = parts[0]
        let fraction = parts.count == 2 ? parts[1] : ""
        guard !(whole.isEmpty && fraction.isEmpty),
              (whole + fraction).allSatisfy({ $0.isASCII && $0.isWholeNumber }),
              fraction.count <= 8,
              let bitcoin = Decimal(string: self, locale: Locale(identifier: "en_US_POSIX"))
        else { return nil }
        
        // Above 21 million bitcoin, this returns nil.
        return bitcoin.satoshisFromBitcoin()
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
