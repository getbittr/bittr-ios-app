//
//  SendURI.swift
//  bittr
//
//  Created by Tom Melters on 2/24/26.
//

import UIKit
import LightningDevKit

extension SendViewController {
    
    func checkForPendingURI() {
        
        if self.pendingBitcoinURI != nil {
            self.setAddressFromURI(address: self.pendingBitcoinURI!.address, amount: self.pendingBitcoinURI!.amount, label: self.pendingBitcoinURI!.label)
            self.pendingBitcoinURI = nil // Clear after handling
        }
        
        if self.pendingLightningURI != nil {
            self.setInvoiceFromURI(invoice: self.pendingLightningURI!)
            self.pendingLightningURI = nil // Clear after handling
        }
    }
    
    func setAddressFromURI(address: String, amount: String, label: String) {
        
        // First, switch to regular (on-chain) mode
        // Look for the regular button and tap it programmatically
        if let regularButton = self.regularButton {
            regularButton.sendActions(for: .touchUpInside)
        }
        
        // Wait a moment for the mode switch to complete, then set the address
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            // Set the address in the text field
            self.toTextField.text = address
            
            // Set the amount if provided
            if !amount.isEmpty {
                // Convert BTC amount to satoshis
                if let btcAmount = Double(amount) {
                    let satoshis = Int(btcAmount * 100_000_000) // Convert BTC to satoshis
                    self.amountTextField.text = "\(satoshis)"
                    self.btcLabel.text = "Sats"
                    self.selectedCurrency = .satoshis
                    print("Converted Bitcoin URI amount from \(amount) BTC to \(satoshis) satoshis")
                } else {
                    // If conversion fails, set the amount as-is (might be in satoshis already)
                    self.amountTextField.text = amount
                    Log.info("Could not convert Bitcoin URI amount.")
                    print("Setting as-is: \(amount)")
                }
            }
            
            print("Set Bitcoin address from URI: \(address), amount: \(amount), label: \(label)")
        }
    }
    
    func setInvoiceFromURI(invoice: String) {
        
        // First, switch to instant (Lightning) mode
        // Look for the instant button and tap it programmatically
        if let instantButton = self.instantButton {
            instantButton.sendActions(for: .touchUpInside)
        }
        
        // Wait a moment for the mode switch to complete, then set the invoice
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            // Set the invoice in the text field
            self.toTextField.text = invoice
            
            // Parse the Lightning invoice to extract the amount
            if invoice.lowercased().hasPrefix("ln") {
                if let parsedInvoice = Bindings.Bolt11Invoice.fromStr(s: invoice).getValue() {
                    if let invoiceAmountMilli = parsedInvoice.amountMilliSatoshis() {
                        let invoiceAmount = Int(invoiceAmountMilli)/1000
                        self.amountTextField.text = "\(invoiceAmount)"
                        self.btcLabel.text = "Sats"
                        self.selectedCurrency = .satoshis
                        print("Extracted amount from Lightning invoice: \(invoiceAmount) sats")
                    } else {
                        Log.info("Lightning invoice has no amount (zero amount invoice)")
                    }
                } else {
                    Log.info("Failed to parse Lightning invoice")
                }
            }
            
            print("Set Lightning invoice from URI: \(invoice)")
        }
    }
    
}
