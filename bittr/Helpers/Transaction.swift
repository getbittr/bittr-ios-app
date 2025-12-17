//
//  Transaction.swift
//  bittr
//
//  Created by Tom Melters on 06/09/2023.
//

import UIKit
import BitcoinDevKit
import LDKNode
import Sentry

class Transaction: NSObject {

    // General
    var id = ""
    var fee = 0
    var received = 0
    var sent = 0
    var timestamp = 0
    var note = ""
    
    // Onchain
    var height = 0
    var confirmations = 0
    
    // Lightning
    var isLightning = false
    var lnDescription = ""
    var channelId = ""
    var isFundingTransaction = false
    
    // Bittr purchases
    var isBittr = false
    var purchaseAmount: CGFloat = 0
    var currency = "EUR"
    var transferFee: CGFloat = 0
    
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

extension PaymentDetails {
    
    func createTransaction(coreVC:CoreViewController?, bittrTransactions:NSMutableDictionary?) -> Transaction {
        
        // Create transaction object.
        let thisTransaction = Transaction()
        
        // ID.
        thisTransaction.id = self.kind.transactionID ?? self.id
        
        // Kind, status, and timestamp.
        switch self.kind {
        case .onchain(txid: _, status: let status):
            // Onchain transaction.
            thisTransaction.isLightning = false
            
            // Set status and timestamp.
            switch status {
            case .confirmed(blockHash: _, height: let height, timestamp: let timestamp):
                thisTransaction.timestamp = Int(timestamp)
                thisTransaction.height = Int(height)
                if let currentHeight = coreVC?.bittrWallet.currentHeight {
                    thisTransaction.confirmations = currentHeight - Int(height) + 1
                }
            case .unconfirmed:
                thisTransaction.timestamp = Int(self.latestUpdateTimestamp)
                thisTransaction.height = 0
                thisTransaction.confirmations = 0
            }
        default:
            // Lightning payment.
            thisTransaction.isLightning = true
            thisTransaction.timestamp = CacheManager.getInvoiceTimestamp(preimage: thisTransaction.id)
            
            // Set channel ID.
            if let actualChannels = coreVC?.bittrWallet.lightningChannels, let activeChannel = actualChannels.getActiveChannel() {
                thisTransaction.channelId = activeChannel.channelId
            }
        }
        
        // Amount
        if self.direction == .inbound {
            thisTransaction.received = Int(self.amountMsat ?? 0)/1000
        } else {
            thisTransaction.sent = Int(self.amountMsat ?? 0)/1000
            if thisTransaction.isLightning {
                thisTransaction.fee = CacheManager.getLightningFees(preimage: thisTransaction.id)
            } else {
                thisTransaction.fee = Int(self.feePaidMsat ?? 0)/1000
            }
        }
        
        // Note and Description.
        thisTransaction.note = CacheManager.getTransactionNote(txid: thisTransaction.id)
        thisTransaction.lnDescription = CacheManager.getInvoiceDescription(preimage: thisTransaction.id)
        
        // Check if transaction is Bittr.
        if bittrTransactions != nil, (bittrTransactions!.allKeys as! [String]).contains(thisTransaction.id) {
            thisTransaction.isBittr = true
            thisTransaction.purchaseAmount = ((bittrTransactions![thisTransaction.id] as! [String:Any])["amount"] as! String).toNumber()
            thisTransaction.currency = (bittrTransactions![thisTransaction.id] as! [String:Any])["currency"] as! String
            if let transferFeeString = (bittrTransactions![thisTransaction.id] as! [String:Any])["transferFee"] as? String {
                let transferFee = transferFeeString.toNumber().inSatoshis()
                thisTransaction.transferFee = CGFloat(transferFee)
            }
        }
        
        // Return new transaction.
        return thisTransaction
    }
}

extension BittrTransaction {
    
    func createTransaction(coreVC:CoreViewController?, isFundingTransaction:Bool) -> Transaction {
        
        // Create transaction object.
        let thisTransaction = Transaction()
        
        thisTransaction.id = self.txId
        thisTransaction.sent = 0
        thisTransaction.received = self.bitcoinAmount.toNumber().inSatoshis()
        thisTransaction.isLightning = true
        thisTransaction.isFundingTransaction = isFundingTransaction
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        let transactionDate = formatter.date(from:self.datetime)!
        let transactionTimestamp = Int(transactionDate.timeIntervalSince1970)
        thisTransaction.timestamp = transactionTimestamp
        
        thisTransaction.isBittr = true
        thisTransaction.purchaseAmount = self.purchaseAmount.toNumber()
        thisTransaction.currency = self.currency
        let transferFee = self.transferFee.toNumber().inSatoshis()
        thisTransaction.transferFee = CGFloat(transferFee)
        thisTransaction.lnDescription = CacheManager.getInvoiceDescription(preimage: self.txId)
        if let actualChannels = coreVC?.bittrWallet.lightningChannels, let activeChannel = actualChannels.getActiveChannel() {
            thisTransaction.channelId = activeChannel.channelId
        }
        
        // Return new transaction.
        return thisTransaction
    }
}
