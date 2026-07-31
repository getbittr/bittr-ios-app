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
    
    // Onchain
    var height:Int?
    
    // Lightning
    var isLightning = false
    var lnDescription = ""
    var channelId = ""
    var isFundingTransaction = false
    var isChannelClosure = false
    
    // Bittr purchases
    var isBittr = false
    var currency = "EUR"
    var fiatNetAmount: CGFloat = 0
    var fiatGrossAmount: CGFloat = 0
    var transferFee: CGFloat = 0
    var surcharge: CGFloat = 0
    var bittrFee: CGFloat = 0
    var historicalExchangeRate: CGFloat = 0
    
    // Swaps
    var isSwap = false
    var isSuggestedSwap = false
    // Whether this payment is a swap's own leg (its cached description is the
    // dateID of a recorded swap). Checked against the swapids cache — which
    // only the swap flows write — rather than by matching the description
    // text, so a look-alike description can't make a payment pass as a swap.
    var isSwapPayment: Bool {
        let description = self.lnDescription != "" ? self.lnDescription : CacheManager.getInvoiceDescription(preimage: self.id)
        return description != "" && CacheManager.getSwapID(dateID: description) != nil
    }
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
    
    func createTransaction(bittrTransactions:[String:BittrTransaction]?) -> Transaction {
        
        // Create transaction object.
        let thisTransaction = Transaction()
        
        // ID.
        thisTransaction.id = self.kind.transactionID ?? self.id
        
        // Kind, status, and timestamp.
        switch self.kind {
        case .onchain(txid: let txid, status: let status):
            // Onchain transaction.
            thisTransaction.isLightning = false
            thisTransaction.isChannelClosure = CacheManager.getChannelClosureTxIDs().contains(txid)
            
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
            if let activeChannel = BitcoinManager.shared.bittrWallet.lightningChannels.getActiveChannel() {
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
        
        // Description.
        thisTransaction.lnDescription = CacheManager.getInvoiceDescription(preimage: thisTransaction.id)
        
        // Check if transaction is Bittr.
        if bittrTransactions != nil, let thisBittrTransaction = bittrTransactions![thisTransaction.id] {
            
            thisTransaction.isBittr = true
            
            // Currency
            thisTransaction.currency = thisBittrTransaction.currency
            
            // Fiat net amount.
            thisTransaction.fiatNetAmount = thisBittrTransaction.fiatNetAmount.toNumber()
            
            // Fiat gross amount.
            thisTransaction.fiatGrossAmount = thisBittrTransaction.fiatGrossAmount.toNumber()
            
            // Transfer fee.
            thisTransaction.transferFee = CGFloat(thisBittrTransaction.transferFee.toNumber().inSatoshis())
            
            // Surcharge.
            thisTransaction.surcharge = thisBittrTransaction.surcharge.toNumber()
            
            // Bittr fee.
            thisTransaction.bittrFee = thisBittrTransaction.bittrFee.toNumber()
            
            // Historical exchange rate.
            thisTransaction.historicalExchangeRate = thisBittrTransaction.historicalExchangeRate.toNumber()
        }
        
        // Return new transaction.
        return thisTransaction
    }
}

extension BittrTransaction {
    
    func createTransaction(isFundingTransaction:Bool) -> Transaction {
        
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
        thisTransaction.fiatNetAmount = self.fiatNetAmount.toNumber()
        thisTransaction.fiatGrossAmount = self.fiatGrossAmount.toNumber()
        thisTransaction.transferFee = CGFloat(self.transferFee.toNumber().inSatoshis())
        thisTransaction.surcharge = self.surcharge.toNumber()
        thisTransaction.bittrFee = self.bittrFee.toNumber()
        thisTransaction.historicalExchangeRate = self.historicalExchangeRate.toNumber()
        
        thisTransaction.lnDescription = CacheManager.getInvoiceDescription(preimage: self.txId)
        if let activeChannel = BitcoinManager.shared.bittrWallet.lightningChannels.getActiveChannel() {
            thisTransaction.channelId = activeChannel.channelId
        }
        
        // Return new transaction.
        return thisTransaction
    }
}

extension Transaction {
    
    func toBittrTransaction() -> BittrTransaction {
        
        let bittrTransaction = BittrTransaction(
            txId: "",
            transferType: "",
            historicalExchangeRate: "\(self.historicalExchangeRate)",
            datetime: "",
            currency: self.currency,
            bitcoinAmount: "",
            transferFee: "\(self.transferFee.inBTC())",
            bittrFee: "\(self.bittrFee)",
            surcharge: "\(self.surcharge)",
            fiatNetAmount: "\(self.fiatNetAmount)",
            fiatGrossAmount: "\(self.fiatGrossAmount)"
        )
        
        return bittrTransaction
    }
    
    func year() -> String {
        let transactionDate = Date(timeIntervalSince1970: Double(self.timestamp))
        let dateFormatter = DateFormatter()
        dateFormatter.timeZone = TimeZone.current
        dateFormatter.dateFormat = "yyyy"
        let yearString = dateFormatter.string(from: transactionDate)
        return yearString
    }
}
