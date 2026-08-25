//
//  CacheStore.swift
//  bittr
//

import Foundation


// MARK: - Keys

struct CacheKey<Value> {
    
    let name:String
    private let isEnvironmentScoped:Bool
    
    init(_ name:String, environmentScoped:Bool = true) {
        self.name = name
        self.isEnvironmentScoped = environmentScoped
    }
    
    var storageKey:String {
        return isEnvironmentScoped ? EnvironmentConfig.cacheKey(for: name) : name
    }
}

// Types UserDefaults can hold as-is, so they don't need to be encoded.
protocol CacheStorable {}

extension String: CacheStorable {}
extension Int: CacheStorable {}
extension Bool: CacheStorable {}
extension Array: CacheStorable where Element: CacheStorable {}
extension Dictionary: CacheStorable where Key == String, Value: CacheStorable {}


// MARK: - Store

enum CacheStore {
    
    private static var defaults:UserDefaults { UserDefaults.standard }
    
    
    // MARK: Plist-native values
    
    static func value<Value: CacheStorable>(for key:CacheKey<Value>) -> Value? {
        return defaults.object(forKey: key.storageKey) as? Value
    }
    
    static func set<Value: CacheStorable>(_ value:Value?, for key:CacheKey<Value>) {
        guard let value = value else {
            defaults.removeObject(forKey: key.storageKey)
            return
        }
        defaults.set(value, forKey: key.storageKey)
    }
    
    
    // MARK: Codable values
    
    static func decoded<Value: Decodable>(for key:CacheKey<Value>) -> Value? {
        guard let data = defaults.data(forKey: key.storageKey) else { return nil }
        do {
            return try JSONDecoder().decode(Value.self, from: data)
        } catch {
            // A cache that can't be read is rebuilt from the node.
            Log.info("Could not decode cache \"\(key.name)\": \(error)")
            return nil
        }
    }
    
    static func encode<Value: Encodable>(_ value:Value?, for key:CacheKey<Value>) {
        guard let value = value else {
            defaults.removeObject(forKey: key.storageKey)
            return
        }
        do {
            defaults.set(try JSONEncoder().encode(value), forKey: key.storageKey)
        } catch {
            Log.info("Could not encode cache \"\(key.name)\": \(error)")
            SentryManager.capture(error, context: "encoding cache \(key.name)")
        }
    }
    
    // Reads a Codable cache, falling back to `migration` when nothing decodes.
    static func decoded<Value: Codable>(for key:CacheKey<Value>, migratingLegacyWith migration:(Any) -> Value?) -> Value? {
        // Check if data is available.
        if let decoded = decoded(for: key) { return decoded }
        
        // Check if non-migrated data is available.
        guard let legacy = plistObject(for: key), let migrated = migration(legacy) else { return nil }
        
        Log.info("Migrated cache \"\(key.name)\" to its Codable form.")
        encode(migrated, for: key)
        return migrated
    }
    
    
    // MARK: Plist values

    // The stored object in whatever plist shape it has.
    static func plistObject<Value>(for key:CacheKey<Value>) -> Any? {
        return defaults.object(forKey: key.storageKey)
    }
    
    static func setPlistObject<Value>(_ value:Any?, for key:CacheKey<Value>) {
        guard let value = value else {
            defaults.removeObject(forKey: key.storageKey)
            return
        }
        defaults.set(value, forKey: key.storageKey)
    }
    
    
    // MARK: Removal
    
    static func remove<Value>(_ key:CacheKey<Value>) {
        defaults.removeObject(forKey: key.storageKey)
    }
    
    
    // MARK: Migration
    
    // Whether this key is still held in its pre-Codable shape.
    static func holdsLegacyShape<Value>(_ key:CacheKey<Value>) -> Bool {
        guard defaults.object(forKey: key.storageKey) != nil else { return false }
        return defaults.data(forKey: key.storageKey) == nil
    }
    
    // Converts a key still held in its pre-Codable shape, and does nothing otherwise.
    static func migrateLegacyValue<Value: Codable>(for key:CacheKey<Value>, with migration:(Any) -> Value?) {
        guard holdsLegacyShape(key), let stored = plistObject(for: key) else { return }
        guard let migrated = migration(stored) else {
            Log.info("Cache \"\(key.name)\" is in an unrecognised shape; leaving it as it is.")
            return
        }
        Log.info("Migrated cache \"\(key.name)\" to its Codable form.")
        encode(migrated, for: key)
    }
}


// MARK: - Cached models

// The funding output of a channel.
struct ChannelOutpoint: Codable {
    
    let txID:String
    let vout:UInt32
    
    init(txID:String, vout:UInt32) {
        self.txID = txID
        self.vout = vout
    }
    
    // Reads the "txid:vout" form written before this was Codable.
    init?(legacyString: String) {
        let components = legacyString.components(separatedBy: ":")
        guard components.count == 2, let vout = UInt32(components[1]) else { return nil }
        self.txID = components[0]
        self.vout = vout
    }
}


// MARK: - Key registry

// Every key this app persists, in one place.
enum CacheKeys {
    
    // MARK: Bittr account

    static let device = CacheKey<[IbanEntity]>("device")
    
    // MARK: Transactions
    
    /// Lightning payments the app has seen, keyed by payment id.
    static let lightningTransactions = CacheKey<[String:Transaction]>("lightning")
    
    /// The Home screen's snapshot: balance, conversion and recent transactions.
    static let walletCache = CacheKey<WalletCache>("walletcache")
    
    /// Payment id -> the moment the invoice was created.
    static let invoiceTimestamps = CacheKey<[String:Int]>("hashes")
    
    /// Payment id -> the description shown for it.
    static let invoiceDescriptions = CacheKey<[String:String]>("descriptions")
    
    /// Payment id -> routing fee actually paid, in satoshis.
    static let paymentFees = CacheKey<[String:Int]>("lightningfees")
    
    /// Transaction id -> the note the user wrote on it.
    static let transactionNotes = CacheKey<[String:String]>("transactionnotes")
    
    /// Transaction ids already reconciled against the Bittr API.
    static let sentToBittr = CacheKey<[String]>("senttobittr")
    
    // MARK: Chain state
    
    static let lastAddress = CacheKey<String>("lastaddress")
    static let txoID = CacheKey<String>("txoid")
    static let channelFundingOutpoint = CacheKey<ChannelOutpoint>("channelfundingoutpoint")
    static let channelClosureTxIDs = CacheKey<[String]>("channelclosuretxids")
    static let onchainAddresses = CacheKey<[OnchainAddress]>("onchainaddresses")
    
    // MARK: Swaps
    
    static let swapIDs = CacheKey<[String:String]>("swapids", environmentScoped: false)
    static let suggestedSwaps = CacheKey<[String:String]>("suggestedswaps", environmentScoped: false)
    static let ongoingSwap = CacheKey<NSDictionary>("ongoingswap", environmentScoped: false)
    static let swapIndex = CacheKey<Int>("swapindex")
    static let lastKnownFeeRate = CacheKey<Int>("lastknownfeerate")
    
    // MARK: App state
    
    static let walletRemovalInProgress = CacheKey<Bool>("walletremovalinprogress")
    static let handledEvents = CacheKey<[String]>("handledevents", environmentScoped: false)
    static let completedLessons = CacheKey<[String]>("completedlessons", environmentScoped: false)
    static let notificationsToken = CacheKey<String>("notificationstoken", environmentScoped: false)

    /// The server-signed Boltz webhook URL (carries the HMAC `token`), and the
    /// APNS device token the server hashed to mint it. Environment-scoped: the
    /// HMAC and host differ between staging and production.
    static let boltzWebhookURL = CacheKey<String>("boltzwebhookurl")
    static let boltzWebhookDeviceToken = CacheKey<String>("boltzwebhookdevicetoken")
    
    // MARK: Preferences
    
    static let currency = CacheKey<String>("currency", environmentScoped: false)
    static let language = CacheKey<String>("language", environmentScoped: false)
    static let darkModeSetting = CacheKey<String>("darkmode", environmentScoped: false)
    static let currentDarkMode = CacheKey<String>("currentdarkmode", environmentScoped: false)
}
