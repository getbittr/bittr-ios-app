//
//  Transaction.swift
//  bittr
//
//  Created by Tom Melters on 06/09/2023.
//

import UIKit
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
    var height:Int?
    
    // Lightning
    var isLightning = false
    var lnDescription = ""
    var channelId = ""
    var isFundingTransaction = false
    
    // Bittr purchases
    var isBittr = false
    var currency = "EUR"
    var purchaseAmount: CGFloat = 0
    var transferFee: CGFloat = 0
    var surcharge: CGFloat = 0
    var bittrFee: CGFloat = 0
    
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
            case .unconfirmed:
                thisTransaction.timestamp = Int(self.latestUpdateTimestamp)
                thisTransaction.height = nil
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
            thisTransaction.currency = (bittrTransactions![thisTransaction.id] as! [String:Any])["currency"] as! String
            thisTransaction.purchaseAmount = ((bittrTransactions![thisTransaction.id] as! [String:Any])["amount"] as! String).toNumber()
            
            // Transfer fee.
            if let transferFeeString = (bittrTransactions![thisTransaction.id] as! [String:Any])["transferFee"] as? String {
                let transferFee = transferFeeString.toNumber().inSatoshis()
                thisTransaction.transferFee = CGFloat(transferFee)
            } else if let transferFee = (bittrTransactions![thisTransaction.id] as! [String:Any])["transferFee"] as? CGFloat {
                thisTransaction.transferFee = transferFee
            }
            
            // Surcharge.
            if let surchargeString = (bittrTransactions![thisTransaction.id] as! [String:Any])["surcharge"] as? String {
                let surcharge = surchargeString.toNumber()
                thisTransaction.surcharge = surcharge
            } else if let surcharge = (bittrTransactions![thisTransaction.id] as! [String:Any])["surcharge"] as? CGFloat {
                thisTransaction.surcharge = surcharge
            }
            
            // Bittr fee.
            if let bittrFeeString = (bittrTransactions![thisTransaction.id] as! [String:Any])["bittrFee"] as? String {
                let bittrFee = bittrFeeString.toNumber()
                thisTransaction.bittrFee = bittrFee
            } else if let bittrFee = (bittrTransactions![thisTransaction.id] as! [String:Any])["bittrFee"] as? CGFloat {
                thisTransaction.bittrFee = bittrFee
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
        
        // Date and time.
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        let transactionDate = formatter.date(from:self.datetime)!
        let transactionTimestamp = Int(transactionDate.timeIntervalSince1970)
        thisTransaction.timestamp = transactionTimestamp
        
        // Bittr details.
        thisTransaction.isBittr = true
        thisTransaction.currency = self.currency
        thisTransaction.purchaseAmount = self.purchaseAmount.toNumber()
        thisTransaction.transferFee = CGFloat(self.transferFee.toNumber().inSatoshis())
        thisTransaction.surcharge = self.surcharge.toNumber()
        thisTransaction.bittrFee = self.bittrFee.toNumber()
        
        thisTransaction.lnDescription = CacheManager.getInvoiceDescription(preimage: self.txId)
        if let actualChannels = coreVC?.bittrWallet.lightningChannels, let activeChannel = actualChannels.getActiveChannel() {
            thisTransaction.channelId = activeChannel.channelId
        }
        
        // Return new transaction.
        return thisTransaction
    }
}
