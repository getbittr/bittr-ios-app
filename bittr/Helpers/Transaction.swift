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

    var id = ""
    var fee = 0
    var received = 0
    var sent = 0
    var height = 0
    var timestamp = 0
    var isBittr = false
    var purchaseAmount: CGFloat = 0
    var currency = "EUR"
    var transferFee: CGFloat = 0
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

extension CanonicalTx {
    
    func createTransaction(coreVC:CoreViewController?, bittrTransactions:NSMutableDictionary?) -> Transaction {
        
        // Create transaction object.
        let thisTransaction = Transaction()
        
        thisTransaction.id = self.transaction.computeTxid()
        thisTransaction.isLightning = false
        thisTransaction.received = Int(LightningNodeService.shared.getWallet()!.sentAndReceived(tx: self.transaction).received.toSat())
        thisTransaction.sent = Int(LightningNodeService.shared.getWallet()!.sentAndReceived(tx: self.transaction).sent.toSat())
        
        // Fees
        do {
            thisTransaction.fee = Int(try LightningNodeService.shared.getWallet()!.calculateFee(tx: self.transaction).toSat())
        } catch {
            print("810 Could not calculate fee.")
            DispatchQueue.main.async {
                SentrySDK.capture(error: error) { scope in
                    scope.setExtra(value: "Transaction row 71", key: "context")
                }
            }
        }
        
        // Height
        switch self.chainPosition {
        case .unconfirmed(timestamp: let timestamp):
            thisTransaction.timestamp = Int(timestamp ?? UInt64(Date().timeIntervalSince1970))
            thisTransaction.height = 0
            thisTransaction.confirmations = 0
        case .confirmed(confirmationBlockTime: let confirmationBlockTime, transitively: _):
            thisTransaction.timestamp = Int(confirmationBlockTime.confirmationTime)
            thisTransaction.height = Int(confirmationBlockTime.blockId.height)
            if let actualCurrentHeight = coreVC?.bittrWallet.currentHeight {
                thisTransaction.confirmations = (actualCurrentHeight - thisTransaction.height) + 1
            }
        }
        
        // Description and note
        thisTransaction.note = CacheManager.getTransactionNote(txid: thisTransaction.id)
        if CacheManager.getInvoiceDescription(preimage: thisTransaction.id) != "" {
            thisTransaction.lnDescription = CacheManager.getInvoiceDescription(preimage: thisTransaction.id)
        }
        
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

extension PaymentDetails {
    
    func createTransaction(coreVC:CoreViewController?, bittrTransactions:NSMutableDictionary?) -> Transaction {
        
        // Create transaction object.
        let thisTransaction = Transaction()
        
        thisTransaction.id = self.kind.preimageAsString ?? self.id
        thisTransaction.note = CacheManager.getTransactionNote(txid: thisTransaction.id)
        if self.direction == .inbound {
            thisTransaction.received = Int(self.amountMsat ?? 0)/1000
        } else {
            thisTransaction.sent = Int(self.amountMsat ?? 0)/1000
            thisTransaction.fee = CacheManager.getLightningFees(preimage: thisTransaction.id)
        }
        thisTransaction.isLightning = true
        thisTransaction.timestamp = CacheManager.getInvoiceTimestamp(preimage: thisTransaction.id)
        thisTransaction.lnDescription = CacheManager.getInvoiceDescription(preimage: thisTransaction.id)
        if let actualChannels = coreVC?.bittrWallet.lightningChannels, actualChannels.first != nil {
            thisTransaction.channelId = actualChannels.first!.channelId
        }
        
        
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
        let transactionDate = formatter.date(from:self.datetime)!
        let transactionTimestamp = Int(transactionDate.timeIntervalSince1970)
        thisTransaction.timestamp = transactionTimestamp
        
        thisTransaction.isBittr = true
        thisTransaction.purchaseAmount = self.purchaseAmount.toNumber()
        thisTransaction.currency = self.currency
        let transferFee = self.transferFee.toNumber().inSatoshis()
        thisTransaction.transferFee = CGFloat(transferFee)
        thisTransaction.lnDescription = CacheManager.getInvoiceDescription(preimage: self.txId)
        if let actualChannels = coreVC?.bittrWallet.lightningChannels, actualChannels.first != nil {
            thisTransaction.channelId = actualChannels.first!.channelId
        }
        
        // Return new transaction.
        return thisTransaction
    }
}
