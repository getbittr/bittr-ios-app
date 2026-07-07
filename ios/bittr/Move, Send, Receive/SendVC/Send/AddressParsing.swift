//
//  AddressParsing.swift
//  bittr
//
//  Created by Tom Melters on 02/07/2024.
//

import UIKit
import LNURLDecoder
import LightningDevKit
import Sentry

extension SendViewController {
    
    func handleScannedOrPastedString(_ code:String) {
        print("Code: " + code)
        
        // Parse code components.
        let bitcoinAddress = code.lowercased().extractBitcoinAddress()
        let lightningInvoice = code.lowercased().extractLightningInvoice()
        let lnurl = code.lowercased().extractLNURL()
        let amount = code.lowercased().extractAmount()
        
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
            if let parsedInvoice = Bindings.Bolt11Invoice.fromStr(s: lightningInvoice!).getValue() {
                if let invoiceAmountMilli = parsedInvoice.amountMilliSatoshis() {
                    // Regular invoice
                    let invoiceAmount = Int(invoiceAmountMilli)/1000

                    let availableLightningBalance = (self.coreVC?.bittrWallet.lightningChannels.getActiveChannel()?.outboundCapacityMsat ?? 0)/1000
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
            }
            
            if bitcoinAddress != nil {
                Log.info("Did also find onchain address.")
                self.bitcoinQR = bitcoinAddress!
            }
        } else if bitcoinAddress != nil {
            Log.info("Did find onchain address.")
            self.toTextField.text = bitcoinAddress!
            self.onchainOrLightning = .onchain
            if amount != nil, amount != 0 {
                self.amountTextField.text = "\(amount!)"
                self.btcLabel.text = "Sats"
                self.selectedCurrency = .satoshis
            }
        } else {
            Log.info("Did not find a valid address or invoice.")
            self.toTextField.text = nil
            self.amountTextField.text = nil
            self.showAlert(presentingController: self, title: Language.getWord(withID: "nobitcoinaddressfound"), message: Language.getWord(withID: "pleasescan"), buttons: [Language.getWord(withID: "okay")], actions: nil)
            return
        }
        
        // Update labels.
        self.updateLabels()
    }
}

extension String {
    
    func extractBitcoinAddress() -> String? {
        let components = self.components(separatedBy: CharacterSet(charactersIn: "&:?="))
        for eachComponent in components {
            if eachComponent.isValidBitcoinAddress() {
                return eachComponent
            }
        }
        return nil
    }
    
    func extractLightningInvoice() -> String? {
        let components = self.components(separatedBy: CharacterSet(charactersIn: "&:?="))
        for eachComponent in components {
            if eachComponent.isValidInvoice() {
                return eachComponent
            }
        }
        return nil
    }
    
    func extractLNURL() -> String? {
        let components = self.components(separatedBy: CharacterSet(charactersIn: "&:?="))
        for eachComponent in components {
            if eachComponent.isValidEmail() {
                return eachComponent
            } else if eachComponent.hasPrefix("lnurl") {
                return eachComponent
            }
        }
        return nil
    }
    
    func extractAmount() -> Int? {
        let components = self.components(separatedBy: CharacterSet(charactersIn: "&:?"))
        for eachComponent in components {
            if eachComponent.contains("amount=") {
                return eachComponent.replacingOccurrences(of: "amount=", with: "").toNumber().inSatoshis()
            }
        }
        return nil
    }
    
    func isValidBitcoinAddress() -> Bool {
        let patterns = [
            "^1[a-km-zA-HJ-NP-Z1-9]{25,34}$",  // P2PKH Mainnet
            "^[mn2][a-km-zA-HJ-NP-Z1-9]{33}$",  // P2PKH or P2SH Testnet
            "^bc1[qzp][a-z0-9]{38,}$",  // Bech32 Mainnet
            "^tb1[qzp][a-z0-9]{38,}$",  // Bech32 Testnet,
            "^bcrt1[qzp][a-z0-9]{38,}$"  // Bech32 Regtest
        ]
        return patterns.contains {
            self.range(of: $0, options: [.regularExpression, .caseInsensitive]) != nil
        }
    }
    
    func isValidInvoice() -> Bool {
        if self.hasPrefix("ln") {
            let bolt11Invoice = Bolt11Invoice.fromStr(s: self)
            if bolt11Invoice.isOk(), bolt11Invoice.getValue() != nil {
                return true
            } else {
                if let _ = self.bolt12Offer() {
                    return true
                } else {
                    return false
                }
            }
        } else {
            return false
        }
    }
}
