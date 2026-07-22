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
    // setValue removes the key when handed nil, so optionals need no guarding.
    func toDictionary() -> NSDictionary {

        let swapDictionary = NSMutableDictionary()
        swapDictionary.setValue(self.dateID, forKey: "dateID")
        swapDictionary.setValue(self.swapDirection == .onchainToLightning, forKey: "onchainToLightning")
        swapDictionary.setValue(self.satoshisAmount, forKey: "satoshisAmount")
        swapDictionary.setValue(self.isSuggested, forKey: "isSuggested")
        swapDictionary.setValue(self.createdInvoice, forKey: "createdInvoice")
        swapDictionary.setValue(self.privateKey, forKey: "privateKey")

        // Boltz reply
        swapDictionary.setValue(self.boltzID, forKey: "boltzID")
        swapDictionary.setValue(self.boltzExpectedAmount, forKey: "boltzExpectedAmount")

        // Fees
        swapDictionary.setValue(self.onchainFees, forKey: "onchainFees")
        swapDictionary.setValue(self.lightningFees, forKey: "lightningFees")
        swapDictionary.setValue(self.feeHigh, forKey: "feeHigh")
        swapDictionary.setValue(self.claimTransactionFee, forKey: "claimTransactionFee")

        // Onchain to Lightning
        swapDictionary.setValue(self.sentOnchainTransactionID, forKey: "sentOnchainTransactionID")
        swapDictionary.setValue(self.boltzOnchainAddress, forKey: "boltzOnchainAddress")
        swapDictionary.setValue(self.refundPublicKey, forKey: "refundPublicKey")
        swapDictionary.setValue(self.claimLeafOutput, forKey: "claimLeafOutput")
        swapDictionary.setValue(self.refundLeafOutput, forKey: "refundLeafOutput")
        swapDictionary.setValue(self.claimPublicKey, forKey: "claimPublicKey")

        // Lightning to Onchain
        swapDictionary.setValue(self.preimage, forKey: "preimage")
        swapDictionary.setValue(self.destinationAddress, forKey: "destinationAddress")
        swapDictionary.setValue(self.boltzInvoice, forKey: "boltzInvoice")
        swapDictionary.setValue(self.lockupTx, forKey: "lockupTx")

        return swapDictionary
    }
    
}

extension NSDictionary {
    
    func toSwap() -> Swap {
        
        let thisSwap = Swap()

        // These four have non-nil defaults, so a missing key must leave them be.
        if let dateID = self["dateID"] as? String {
            thisSwap.dateID = dateID
        }
        if let onchainToLightning = self["onchainToLightning"] as? Bool {
            thisSwap.swapDirection = onchainToLightning ? .onchainToLightning : .lightningToOnchain
        }
        if let satoshisAmount = self["satoshisAmount"] as? Int {
            thisSwap.satoshisAmount = satoshisAmount
        }
        if let isSuggested = self["isSuggested"] as? Bool {
            thisSwap.isSuggested = isSuggested
        }

        // The rest start out nil, so assigning a failed cast is a no-op.
        thisSwap.createdInvoice = self["createdInvoice"] as? String
        thisSwap.privateKey = self["privateKey"] as? String

        // Boltz reply
        thisSwap.boltzID = self["boltzID"] as? String
        thisSwap.boltzExpectedAmount = self["boltzExpectedAmount"] as? Int

        // Fees
        thisSwap.onchainFees = self["onchainFees"] as? Int
        thisSwap.lightningFees = self["lightningFees"] as? Int
        thisSwap.feeHigh = self["feeHigh"] as? Float
        thisSwap.claimTransactionFee = self["claimTransactionFee"] as? Int

        // Onchain to Lightning
        thisSwap.sentOnchainTransactionID = self["sentOnchainTransactionID"] as? String
        thisSwap.boltzOnchainAddress = self["boltzOnchainAddress"] as? String
        thisSwap.refundPublicKey = self["refundPublicKey"] as? String
        thisSwap.claimLeafOutput = self["claimLeafOutput"] as? String
        thisSwap.refundLeafOutput = self["refundLeafOutput"] as? String
        thisSwap.claimPublicKey = self["claimPublicKey"] as? String

        // Lightning to Onchain
        thisSwap.preimage = self["preimage"] as? String
        thisSwap.destinationAddress = self["destinationAddress"] as? String
        thisSwap.boltzInvoice = self["boltzInvoice"] as? String
        thisSwap.lockupTx = self["lockupTx"] as? String

        return thisSwap
    }
}
