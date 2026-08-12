//
//  Transaction.swift
//  bittr
//
//  Created by Tom Melters on 06/09/2023.
//

import UIKit
import LDKNode

class Transaction: NSObject, Codable {

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
    var isChannelClosure:Bool { return CacheManager.getChannelClosureTxIDs().contains(self.id) }
    
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
    
    enum CodingKeys: String, CodingKey {
        case id, fee, received, sent, timestamp, height
        case isLightning, lnDescription, channelId, isFundingTransaction
        case isBittr, currency, fiatNetAmount, fiatGrossAmount
        case transferFee, surcharge, bittrFee, historicalExchangeRate
        case isSwap, swapStatus, swapDirection
        case onchainID, lightningID, boltzSwapId
    }
    
    convenience init?(legacyDictionary dictionary:NSDictionary) {
        
        guard let timestamp = dictionary["timestamp"] as? Int, timestamp != 0 else { return nil }
        
        self.init()
        
        self.id = dictionary["id"] as? String ?? ""
        self.fee = dictionary["fee"] as? Int ?? 0
        self.received = dictionary["received"] as? Int ?? 0
        self.sent = dictionary["sent"] as? Int ?? 0
        self.timestamp = timestamp
        self.height = dictionary["height"] as? Int
        self.isLightning = dictionary["isLightning"] as? Bool ?? false
        self.lnDescription = dictionary["lnDescription"] as? String ?? ""
        self.channelId = dictionary["channelId"] as? String ?? ""
        self.isFundingTransaction = dictionary["isFundingTransaction"] as? Bool ?? false
        self.isBittr = dictionary["isBittr"] as? Bool ?? false
        self.currency = dictionary["currency"] as? String ?? "EUR"
        self.fiatNetAmount = dictionary["fiatNetAmount"] as? CGFloat ?? 0
        self.fiatGrossAmount = dictionary["fiatGrossAmount"] as? CGFloat ?? 0
        self.transferFee = dictionary["transferFee"] as? CGFloat ?? 0
        self.surcharge = dictionary["surcharge"] as? CGFloat ?? 0
        self.bittrFee = dictionary["bittrFee"] as? CGFloat ?? 0
        self.historicalExchangeRate = dictionary["historicalExchangeRate"] as? CGFloat ?? 0
        self.isSwap = dictionary["isswap"] as? Bool ?? false
        self.onchainID = dictionary["onchainid"] as? String ?? ""
        self.lightningID = dictionary["lightningid"] as? String ?? ""
        self.boltzSwapId = dictionary["boltzSwapId"] as? String ?? ""
        
        self.swapDirection = (dictionary["swapdirection"] as? Int)
            .flatMap { SwapDirection(legacyValue: $0) } ?? .onchainToLightning
        
        self.swapStatus = (dictionary["swapstatus"] as? String)
            .flatMap { SwapStatus(rawValue: $0) } ?? (self.isSwap ? .pending : .succeeded)
    }
}

enum SwapDirection: String, Codable {
    case onchainToLightning
    case lightningToOnchain
    
    init?(legacyValue: Int) {
        switch legacyValue {
        case 0: self = .onchainToLightning
        case 1: self = .lightningToOnchain
        default: return nil
        }
    }
    
    // Cached records written before this was a raw-value enum hold 0 or 1.
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let raw = try? container.decode(String.self), let direction = SwapDirection(rawValue: raw) {
            self = direction
        } else if let legacy = try? container.decode(Int.self), let direction = SwapDirection(legacyValue: legacy) {
            self = direction
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unreadable swap direction.")
        }
    }
}

enum SwapStatus: String, Codable {
    case pending
    case succeeded
    case failed
    
    // A status we can't read becomes pending.
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        self = SwapStatus(rawValue: raw) ?? .pending
    }
}

extension PaymentDetails {
    
    func createTransaction(bittrTransactions:[String:BittrTransaction]?) -> Transaction {
        
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
