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
        get { readCache().transactions?.filter { $0.timestamp != 0 } }
        set { mutateCache { $0.transactions = newValue } }
    }
    
    static func migrateWalletCacheIfNeeded() {
        guard CacheStore.plistObject(for: legacyWalletCacheKey) != nil else { return }
        _ = readCache()
    }
    
    fileprivate static let legacyWalletCacheKey = CacheKey<WalletCache>("cache")
    
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
        if let cache = CacheStore.decoded(for: CacheKeys.walletCache) { return cache }
        
        guard let legacy = CacheStore.plistObject(for: legacyWalletCacheKey) as? NSDictionary else {
            return WalletCache()
        }
        
        var cache = WalletCache()
        cache.satsBalance = legacy["satsbalance"] as? String
        cache.conversion = legacy["conversion"] as? String
        cache.eurValue = legacy["eurvalue"] as? CGFloat
        cache.chfValue = legacy["chfvalue"] as? CGFloat
        cache.height = legacy["height"] as? Int
        if let legacyTransactions = legacy["transactions"] as? [NSDictionary] {
            cache.transactions = legacyTransactions.compactMap { Transaction(legacyDictionary: $0) }
        }
        
        saveCacheLocked(cache)
        CacheStore.remove(legacyWalletCacheKey)
        return cache
    }
    
    /// Persists the cache. Must only be called on `cacheQueue`.
    private static func saveCacheLocked(_ cache: WalletCache) {
        CacheStore.encode(cache, for: CacheKeys.walletCache)
    }
}

struct WalletCache: Codable {
    var satsBalance: String?
    var conversion: String?
    var eurValue: CGFloat?
    var chfValue: CGFloat?
    var height: Int?
    var transactions: [Transaction]?
}
