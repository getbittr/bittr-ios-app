//
//  WalletCache.swift
//  bittr
//
//  Created by Tom Melters on 7/21/26.
//

import UIKit

extension CacheManager {
    
    private static let cacheQueue = DispatchQueue(label: "com.bittr.CacheManager.walletCache")
    
    static var cachedSatsBalance: String? {
        get { readCache().satsBalance }
        set { mutateCache { $0.satsBalance = newValue } }
    }
    
    static var cachedConversion: String? {
        get { readCache().conversion }
        set { mutateCache { $0.conversion = newValue } }
    }
    
    static var cachedEurValue: CGFloat? {
        get { readCache().eurValue }
        set { mutateCache { $0.eurValue = newValue } }
    }
    
    static var cachedChfValue: CGFloat? {
        get { readCache().chfValue }
        set { mutateCache { $0.chfValue = newValue } }
    }
    
    static var cachedHeight: Int? {
        get { readCache().height }
        set { mutateCache { $0.height = newValue } }
    }
    
    static var cachedHomeTransactions: [Transaction]? {
        get {
            guard let records = readCache().transactions else { return nil }
            return records.map { $0.toTransaction() }.filter { $0.timestamp != 0 }
        }
        set { mutateCache { $0.transactions = newValue?.map { CachedTransaction($0) } } }
    }
    
    private static func readCache() -> WalletCache {
        cacheQueue.sync { loadCacheLocked() }
    }
    
    private static func mutateCache(_ body: (inout WalletCache) -> Void) {
        cacheQueue.sync {
            var cache = loadCacheLocked()
            body(&cache)
            saveCacheLocked(cache)
        }
    }
    
    private static func loadCacheLocked() -> WalletCache {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: EnvironmentConfig.cacheKey(for: "walletcache")),
           let cache = try? JSONDecoder().decode(WalletCache.self, from: data) {
            return cache
        }
        guard let legacy = defaults.value(forKey: EnvironmentConfig.cacheKey(for: "cache")) as? NSDictionary else {
            return WalletCache()
        }
        var cache = WalletCache()
        cache.satsBalance = legacy["satsbalance"] as? String
        cache.conversion = legacy["conversion"] as? String
        cache.eurValue = legacy["eurvalue"] as? CGFloat
        cache.chfValue = legacy["chfvalue"] as? CGFloat
        cache.height = legacy["height"] as? Int
        if let legacyTransactions = legacy["transactions"] as? [NSDictionary] {
            cache.transactions = self.getTransactions(transactionsDict: legacyTransactions).map { CachedTransaction($0) }
        }
        saveCacheLocked(cache)
        defaults.removeObject(forKey: EnvironmentConfig.cacheKey(for: "cache"))
        return cache
    }
    
    /// Persists the cache. Must only be called on `cacheQueue`.
    private static func saveCacheLocked(_ cache: WalletCache) {
        guard let data = try? JSONEncoder().encode(cache) else { return }
        UserDefaults.standard.set(data, forKey: EnvironmentConfig.cacheKey(for: "walletcache"))
    }
}

struct WalletCache: Codable {
    var satsBalance: String?
    var conversion: String?
    var eurValue: CGFloat?
    var chfValue: CGFloat?
    var height: Int?
    var transactions: [CachedTransaction]?
}

struct CachedTransaction: Codable {
    var id: String
    var fiatNetAmount: CGFloat
    var fiatGrossAmount: CGFloat
    var transferFee: CGFloat
    var surcharge: CGFloat
    var bittrFee: CGFloat
    var historicalExchangeRate: CGFloat
    var received: Int
    var sent: Int
    var isBittr: Bool
    var timestamp: Int
    var currency: String
    var height: Int?
    var isLightning: Bool
    var fee: Int
    var channelId: String
    var isFundingTransaction: Bool
    var lnDescription: String
    var isSwap: Bool
    var swapStatus: String
    var onchainID: String
    var lightningID: String
    var boltzSwapId: String
    var swapDirection: Int

    init(_ transaction: Transaction) {
        self.id = transaction.id
        self.fiatNetAmount = transaction.fiatNetAmount
        self.fiatGrossAmount = transaction.fiatGrossAmount
        self.transferFee = transaction.transferFee
        self.surcharge = transaction.surcharge
        self.bittrFee = transaction.bittrFee
        self.historicalExchangeRate = transaction.historicalExchangeRate
        self.received = transaction.received
        self.sent = transaction.sent
        self.isBittr = transaction.isBittr
        self.timestamp = transaction.timestamp
        self.currency = transaction.currency
        self.height = transaction.height
        self.isLightning = transaction.isLightning
        self.fee = transaction.fee
        self.channelId = transaction.channelId
        self.isFundingTransaction = transaction.isFundingTransaction
        self.lnDescription = transaction.lnDescription
        self.isSwap = transaction.isSwap
        switch transaction.swapStatus {
        case .pending: self.swapStatus = "pending"
        case .succeeded: self.swapStatus = "succeeded"
        case .failed: self.swapStatus = "failed"
        }
        self.onchainID = transaction.onchainID
        self.lightningID = transaction.lightningID
        self.boltzSwapId = transaction.boltzSwapId
        self.swapDirection = transaction.swapDirection == .onchainToLightning ? 0 : 1
    }

    func toTransaction() -> Transaction {
        let transaction = Transaction()
        transaction.id = id
        transaction.fiatNetAmount = fiatNetAmount
        transaction.fiatGrossAmount = fiatGrossAmount
        transaction.transferFee = transferFee
        transaction.surcharge = surcharge
        transaction.bittrFee = bittrFee
        transaction.historicalExchangeRate = historicalExchangeRate
        transaction.received = received
        transaction.sent = sent
        transaction.isBittr = isBittr
        transaction.timestamp = timestamp
        transaction.currency = currency
        transaction.height = height
        transaction.isLightning = isLightning
        transaction.fee = fee
        transaction.channelId = channelId
        transaction.isFundingTransaction = isFundingTransaction
        transaction.lnDescription = lnDescription
        transaction.isSwap = isSwap
        switch swapStatus {
        case "pending": transaction.swapStatus = .pending
        case "failed": transaction.swapStatus = .failed
        default: transaction.swapStatus = .succeeded
        }
        transaction.onchainID = onchainID
        transaction.lightningID = lightningID
        transaction.boltzSwapId = boltzSwapId
        transaction.swapDirection = swapDirection == 0 ? .onchainToLightning : .lightningToOnchain
        return transaction
    }
}
