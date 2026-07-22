//
//  Swap.swift
//  bittr
//
//  Created by Tom Melters on 15/07/2025.
//

import UIKit

class Swap: NSObject {

    var dateID = ""
    var swapDirection:SwapDirection = .onchainToLightning
    var isSuggested = false
    var satoshisAmount:Int = 0
    var createdInvoice:String?
    var privateKey:String?
    
    // Boltz reply
    var boltzID:String?
    var boltzExpectedAmount:Int?
    
    // Fees
    var onchainFees:Int?
    var lightningFees:Int?
    var feeHigh:Float?
    var claimTransactionFee:Int? // Fee for claiming lightning-to-onchain swaps
    
    // Onchain to Lightning
    var sentOnchainTransactionID:String?
    var boltzOnchainAddress:String?
    var refundPublicKey:String?
    var claimLeafOutput:String?
    var refundLeafOutput:String?
    var claimPublicKey:String?
    
    // Lightning to Onchain
    var sentLightningPaymentID:String?
    var preimage:String?
    var destinationAddress:String?
    var boltzInvoice:String?
    var lockupTx:String?
    
    
    // MARK: - Fees
    
    var definiteFees:Int {
        if self.swapDirection == .lightningToOnchain {
            // The claim fee is deliberately absent: lightningToOnchain adds it to
            // the amount requested from Boltz, so onchainFees — the invoice spread
            // — already contains it. Adding it here would count it twice.
            return (self.onchainFees ?? 0)
        } else {
            // claimTransactionFee is always nil on this side: in an onchain-to-
            // lightning swap Boltz claims the locked funds, so the user never
            // broadcasts a claim transaction. The term is kept for symmetry.
            return (self.onchainFees ?? 0) + (self.lightningFees ?? 0) + (self.claimTransactionFee ?? 0)
        }
    }
    
    var maximumRoutingFee:Int {
        guard self.swapDirection == .lightningToOnchain else { return 0 }
        return self.lightningFees ?? 0
    }
    
    /// A route has to be paid for, so the total isn't fully known up front.
    private var hasRoutingFee:Bool {
        return self.maximumRoutingFee > 0
    }
    
    var minimumTotalFees:Int {
        // Assume a route costs at least 1 sat whenever one is needed.
        return self.definiteFees + (self.hasRoutingFee ? 1 : 0)
    }
    
    var maximumTotalFees:Int {
        return self.definiteFees + self.maximumRoutingFee
    }
    
    /// True only when the two ends of the range actually differ. A maximum routing
    /// fee of exactly 1 sat leaves minimum equal to maximum, and quoting "between
    /// X and X" reads as a bug rather than a range.
    var hasVariableFee:Bool {
        return self.minimumTotalFees < self.maximumTotalFees
    }
    
    func formattedTotalFees() -> String {
        guard self.hasVariableFee else { return "\(self.maximumTotalFees)".addSpaces() }
        return "\(self.minimumTotalFees)".addSpaces() + " - " + "\(self.maximumTotalFees)".addSpaces()
    }
    
    
    // MARK: - Cache conversions
    
    // Convert to NSDictionary.
    func toDictionary() -> NSDictionary {
        
        var onchainToLightning = true
        if self.swapDirection == .lightningToOnchain { onchainToLightning = false }
        let swapDictionary:NSMutableDictionary = ["dateID":self.dateID, "onchainToLightning":onchainToLightning, "satoshisAmount":self.satoshisAmount, "isSuggested":self.isSuggested]
        if self.createdInvoice != nil {
            swapDictionary.setValue(self.createdInvoice!, forKey: "createdInvoice")
        }
        if self.privateKey != nil {
            swapDictionary.setValue(self.privateKey!, forKey: "privateKey")
        }
        if self.boltzID != nil {
            swapDictionary.setValue(self.boltzID!, forKey: "boltzID")
        }
        if self.boltzOnchainAddress != nil {
            swapDictionary.setValue(self.boltzOnchainAddress!, forKey: "boltzOnchainAddress")
        }
        if self.boltzExpectedAmount != nil {
            swapDictionary.setValue(self.boltzExpectedAmount!, forKey: "boltzExpectedAmount")
        }
        if self.onchainFees != nil {
            swapDictionary.setValue(self.onchainFees!, forKey: "onchainFees")
        }
        if self.lightningFees != nil {
            swapDictionary.setValue(self.lightningFees!, forKey: "lightningFees")
        }
        if self.feeHigh != nil {
            swapDictionary.setValue(self.feeHigh!, forKey: "feeHigh")
        }
        if self.claimTransactionFee != nil {
            swapDictionary.setValue(self.claimTransactionFee!, forKey: "claimTransactionFee")
        }
        if self.sentOnchainTransactionID != nil {
            swapDictionary.setValue(self.sentOnchainTransactionID!, forKey: "sentOnchainTransactionID")
        }
        if self.boltzOnchainAddress != nil {
            swapDictionary.setValue(self.boltzOnchainAddress!, forKey: "boltzOnchainAddress")
        }
        if self.refundPublicKey != nil {
            swapDictionary.setValue(self.refundPublicKey!, forKey: "refundPublicKey")
        }
        if self.claimLeafOutput != nil {
            swapDictionary.setValue(self.claimLeafOutput!, forKey: "claimLeafOutput")
        }
        if self.refundLeafOutput != nil {
            swapDictionary.setValue(self.refundLeafOutput!, forKey: "refundLeafOutput")
        }
        if self.claimPublicKey != nil {
            swapDictionary.setValue(self.claimPublicKey!, forKey: "claimPublicKey")
        }
        if self.preimage != nil {
            swapDictionary.setValue(self.preimage!, forKey: "preimage")
        }
        if self.destinationAddress != nil {
            swapDictionary.setValue(self.destinationAddress!, forKey: "destinationAddress")
        }
        if self.boltzInvoice != nil {
            swapDictionary.setValue(self.boltzInvoice!, forKey: "boltzInvoice")
        }
        if self.lockupTx != nil {
            swapDictionary.setValue(self.lockupTx!, forKey: "lockupTx")
        }
        
        return swapDictionary
    }
    
}

extension NSDictionary {
    
    func toSwap() -> Swap {
        
        let thisSwap = Swap()
        if let dateID = self["dateID"] as? String {
            thisSwap.dateID = dateID
        }
        if let onchainToLightning = self["onchainToLightning"] as? Bool {
            thisSwap.swapDirection = .onchainToLightning
            if !onchainToLightning {
                thisSwap.swapDirection = .lightningToOnchain
            }
        }
        if let satoshisAmount = self["satoshisAmount"] as? Int {
            thisSwap.satoshisAmount = satoshisAmount
        }
        if let isSuggested = self["isSuggested"] as? Bool {
            thisSwap.isSuggested = isSuggested
        }
        if let createdInvoice = self["createdInvoice"] as? String {
            thisSwap.createdInvoice = createdInvoice
        }
        if let privateKey = self["privateKey"] as? String {
            thisSwap.privateKey = privateKey
        }
        if let boltzID = self["boltzID"] as? String {
            thisSwap.boltzID = boltzID
        }
        if let boltzOnchainAddress = self["boltzOnchainAddress"] as? String {
            thisSwap.boltzOnchainAddress = boltzOnchainAddress
        }
        if let boltzExpectedAmount = self["boltzExpectedAmount"] as? Int {
            thisSwap.boltzExpectedAmount = boltzExpectedAmount
        }
        if let onchainFees = self["onchainFees"] as? Int {
            thisSwap.onchainFees = onchainFees
        }
        if let lightningFees = self["lightningFees"] as? Int {
            thisSwap.lightningFees = lightningFees
        }
        if let feeHigh = self["feeHigh"] as? Float {
            thisSwap.feeHigh = feeHigh
        }
        if let claimTransactionFee = self["claimTransactionFee"] as? Int {
            thisSwap.claimTransactionFee = claimTransactionFee
        }
        if let sentOnchainTransactionID = self["sentOnchainTransactionID"] as? String {
            thisSwap.sentOnchainTransactionID = sentOnchainTransactionID
        }
        if let boltzOnchainAddress = self["boltzOnchainAddress"] as? String {
            thisSwap.boltzOnchainAddress = boltzOnchainAddress
        }
        if let refundPublicKey = self["refundPublicKey"] as? String {
            thisSwap.refundPublicKey = refundPublicKey
        }
        if let claimLeafOutput = self["claimLeafOutput"] as? String {
            thisSwap.claimLeafOutput = claimLeafOutput
        }
        if let refundLeafOutput = self["refundLeafOutput"] as? String {
            thisSwap.refundLeafOutput = refundLeafOutput
        }
        if let claimPublicKey = self["claimPublicKey"] as? String {
            thisSwap.claimPublicKey = claimPublicKey
        }
        if let preimage = self["preimage"] as? String {
            thisSwap.preimage = preimage
        }
        if let destinationAddress = self["destinationAddress"] as? String {
            thisSwap.destinationAddress = destinationAddress
        }
        if let boltzInvoice = self["boltzInvoice"] as? String {
            thisSwap.boltzInvoice = boltzInvoice
        }
        if let lockupTx = self["lockupTx"] as? String {
            thisSwap.lockupTx = lockupTx
        }
        return thisSwap
    }
}
