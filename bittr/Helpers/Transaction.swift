//
//  Transaction.swift
//  bittr
//
//  Created by Tom Melters on 06/09/2023.
//

import UIKit

class Transaction: NSObject {

    var id = ""
    var fee = 0
    var received = 0
    var sent = 0
    var height = 0
    var timestamp = 0
    var isBittr = false
    var purchaseAmount = 0
    var currency = "EUR"
    var isLightning = false
    var lnDescription = ""
    var confirmations = 0
    var note = ""
    var channelId = ""
    var isFundingTransaction = false
    
    // Swaps
    var isSwap = false
    var swapStatus:SwapStatus = .succeeded
    var swapDirection:SwapDirection = .onchainToLightning
    var onchainID = ""
    var lightningID = ""
    var boltzSwapId = ""
    
}

enum SwapDirection {
    case onchainToLightning
    case lightningToOnchain
}

enum SwapStatus {
    case pending
    case succeeded
    case failed
}
