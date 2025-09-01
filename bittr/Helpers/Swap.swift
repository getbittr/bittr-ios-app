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
    
}
