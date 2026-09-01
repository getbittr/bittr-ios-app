//
//  CacheManager.swift
//  bittr
//
//  Created by Tom Melters on 24/06/2023.
//

import UIKit
import CryptoKit

class CacheManager: NSObject {
    
    static func deleteClientInfo() {
        
        CacheStore.remove(CacheKeys.device)
        CacheStore.remove(CacheKeys.walletCache)
        CacheStore.remove(CacheKeys.lastAddress)
        CacheStore.remove(CacheKeys.lightningTransactions)
        CacheStore.remove(CacheKeys.onchainAddresses)
        CacheStore.remove(CacheKeys.channelFundingOutpoint)
        CacheStore.remove(CacheKeys.channelClosureTxIDs)
        
        // Old keys no longer in use.
        for retired in ["cache", "bittraddress", "pin", "mnemonic"] {
            CacheStore.remove(CacheKey<String>(retired))
        }
        
        // Remove the secrets from the Keychain.
        SecureStore.remove(account: EnvironmentConfig.cacheKey(for: "mnemonic"))
        SecureStore.remove(account: EnvironmentConfig.cacheKey(for: "pin"))
        
        // Clear the ongoing-swap record and sweep the per-swap refund keys out of the Keychain.
        CacheStore.remove(CacheKeys.ongoingSwap)
        SecureStore.removeAll(accountPrefix: "swapkey_")
        
        self.resetFailedPinAttempts()
    }
    
    
    // MARK: - Cache migration
    
    static func migrateCachesIfNeeded() {
        CacheStore.migrateLegacyValue(for: CacheKeys.device, with: legacyIbans)
        CacheStore.migrateLegacyValue(for: CacheKeys.lightningTransactions, with: legacyLightningTransactions)
        CacheStore.migrateLegacyValue(for: CacheKeys.onchainAddresses, with: legacyOnchainAddresses)
        CacheStore.migrateLegacyValue(for: CacheKeys.channelFundingOutpoint, with: legacyChannelOutpoint)
        migrateWalletCacheIfNeeded()
    }
    
    private static func legacyIbans(_ legacy:Any) -> [IbanEntity]? {
        guard let device = legacy as? NSDictionary else { return nil }
        return IbanEntity.fromLegacyDeviceDictionary(device)
    }
    
    private static func legacyLightningTransactions(_ legacy:Any) -> [String:Transaction]? {
        guard let cached = legacy as? NSDictionary else { return nil }
        var transactions = [String:Transaction]()
        for (identifier, values) in cached {
            guard let identifier = identifier as? String,
                  let values = values as? NSDictionary,
                  let transaction = Transaction(legacyDictionary: values) else { continue }
            transactions[identifier] = transaction
        }
        return transactions
    }
    
    private static func legacyOnchainAddresses(_ legacy:Any) -> [OnchainAddress]? {
        guard let stored = legacy as? [NSDictionary] else { return nil }
        return stored.toLegacyAddresses()
    }
    
    private static func legacyChannelOutpoint(_ legacy:Any) -> ChannelOutpoint? {
        guard let stored = legacy as? String else { return nil }
        return ChannelOutpoint(legacyString: stored)
    }
    
    
    // MARK: - Bittr signup details
    
    static func parseDevice() -> BittrWallet {
        
        // Create Bittr wallet.
        let bittrWallet = BittrWallet()
        bittrWallet.ibanEntities = storedIbans()
        return bittrWallet
    }
    
    static func addIban(iban:IbanEntity) {
        
        var ibans = storedIbans()
        
        if let existing = ibans.first(where: { $0.id == iban.id }) {
            // Known IBAN: the caller only supplies these two.
            existing.yourIbanNumber = iban.yourIbanNumber
            existing.yourEmail = iban.yourEmail
        } else {
            ibans += [iban]
        }
        
        storeIbans(ibans)
    }
    
    private static func storedIbans() -> [IbanEntity] {
        let ibans = CacheStore.decoded(for: CacheKeys.device, migratingLegacyWith: legacyIbans)
        return (ibans ?? []).sorted { $0.order < $1.order }
    }

    private static func storeIbans(_ ibans:[IbanEntity]) {
        CacheStore.encode(ibans.sorted { $0.order < $1.order }, for: CacheKeys.device)
    }
    
    private static func updateIban(id:String, _ change:(IbanEntity) -> Void) {
        let ibans = storedIbans()
        guard let iban = ibans.first(where: { $0.id == id }) else { return }
        change(iban)
        storeIbans(ibans)
    }
    
    static func addEmailToken(ibanID:String, emailToken:String) {
        updateIban(id: ibanID) { $0.emailToken = emailToken }
    }
    
    static func setPaymentMode(ibanID:String, paymentMode:String) {
        updateIban(id: ibanID) { $0.paymentMode = paymentMode }
    }
    
    static func addBittrIban(ibanID:String, ourIban:String, ourSwift:String, yourCode:String, lightningAddressUsername:String?) {
        updateIban(id: ibanID) { iban in
            iban.ourIbanNumber = ourIban
            iban.yourUniqueCode = yourCode
            iban.ourSwift = ourSwift
            iban.lightningAddressUsername = lightningAddressUsername ?? iban.lightningAddressUsername
        }
    }
    
    // MARK: - Images cache
    
    static func storeImageInCache(key:String, data:Data) {
        
        // Get the documents directory
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileURL = documentsPath.appendingPathComponent("images/" + key)
        
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)
            // Write the data to file
            try data.write(to: fileURL)
            Log.info("Did save image to file.")
        } catch {
            Log.info("Could not save image to file. \(error.localizedDescription)")
            SentryManager.capture(error, context: "CacheManager row 232")
        }
    }
    
    static func emptyImage() {
        
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let imagesDirectory = documentsPath.appendingPathComponent("images")
        
        do {
            if FileManager.default.fileExists(atPath: imagesDirectory.path) {
                try FileManager.default.removeItem(at: imagesDirectory)
                Log.info("Successfully deleted images folder and its contents.")
            } else {
                Log.info("Images folder does not exist.")
            }
        } catch {
            Log.info("Could not delete images folder. \(error.localizedDescription)")
            SentryManager.capture(error, context: "CacheManager row 53")
        }
    }
    
    static func getImage(key:String) -> Data? {
        
        do {
            // Get the documents directory
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let fileURL = documentsPath.appendingPathComponent("images/" + key)
            
            // Read the JSON data from file
            let imageData = try Data(contentsOf: fileURL)
            
            return imageData
        } catch {
            Log.info("Image not found in cache. \(error.localizedDescription)")
            return nil
        }
    }
    
    // MARK: - Transactions
    
    private static func lightningTransactions() -> [String:Transaction] {
        return CacheStore.decoded(for: CacheKeys.lightningTransactions, migratingLegacyWith: legacyLightningTransactions) ?? [:]
    }
    
    static func storeLightningTransaction(_ thisTransaction:Transaction) {
        var transactions = lightningTransactions()
        transactions[thisTransaction.id] = thisTransaction
        CacheStore.encode(transactions, for: CacheKeys.lightningTransactions)
    }
    
    static func getLightningTransactions() -> [Transaction] {
        return lightningTransactions().values.filter { $0.timestamp != 0 }
    }
    
    
    // MARK: - Keyed caches
    
    private static func keyedCache<Value: CacheStorable>(_ key:CacheKey<[String:Value]>) -> [String:Value] {
        return CacheStore.value(for: key) ?? [:]
    }
    
    private static func setKeyedCache<Value: CacheStorable>(_ key:CacheKey<[String:Value]>, _ entryKey:String, to value:Value?) {
        var cache = keyedCache(key)
        cache[entryKey] = value
        CacheStore.set(cache, for: key)
    }
    
    
    // MARK: - Notifications token
    
    static func storeNotificationsToken(token:String) {
        CacheStore.set(token, for: CacheKeys.notificationsToken)
    }
    
    static func getRegistrationToken() -> String? {
        return CacheStore.value(for: CacheKeys.notificationsToken)
    }

    // MARK: - Boltz webhook token

    /// Persist the server-signed Boltz webhook URL alongside the device token it
    /// was minted for, so a token rotation can be detected and re-minted.
    static func storeBoltzWebhook(url:String, deviceToken:String) {
        CacheStore.set(url, for: CacheKeys.boltzWebhookURL)
        CacheStore.set(deviceToken, for: CacheKeys.boltzWebhookDeviceToken)
    }

    static func getBoltzWebhookURL() -> String? {
        return CacheStore.value(for: CacheKeys.boltzWebhookURL)
    }

    static func getBoltzWebhookDeviceToken() -> String? {
        return CacheStore.value(for: CacheKeys.boltzWebhookDeviceToken)
    }
    
    // MARK: - Invoice timestamp
    
    static func storeInvoiceTimestamp(preimage:String, timestamp:Int) {
        setKeyedCache(CacheKeys.invoiceTimestamps, preimage, to: timestamp)
        Log.info("Timestamp cached.")
    }
    
    static func getInvoiceTimestamp(preimage:String) -> Int {
        
        if let cached = keyedCache(CacheKeys.invoiceTimestamps)[preimage] { return cached }
        
        let now = Int(Date().timeIntervalSince1970)
        self.storeInvoiceTimestamp(preimage: preimage, timestamp: now)
        return now
    }
    
    // MARK: - Swap ID
    
    static func storeSwapID(dateID:String, swapID:String) {
        setKeyedCache(CacheKeys.swapIDs, dateID, to: swapID)
    }
    
    static func getSwapID(dateID:String) -> String? {
        return keyedCache(CacheKeys.swapIDs)[dateID]
    }
    
    // MARK: - Suggested swaps

    // Each entry holds the swap's last observed status ("pending" until the
    // recipient is actually paid, then "succeeded" or "failed"), so the Home
    // table never shows a suggested swap as succeeded before it completes.
    static func storeSuggestedSwap(dateID:String, status:SwapStatus = .pending) {
        setKeyedCache(CacheKeys.suggestedSwaps, dateID, to: status.rawValue)
    }

    static func getSuggestedSwapStatus(dateID:String) -> SwapStatus? {
        guard let value = CacheStore.plistObject(for: CacheKeys.suggestedSwaps)
            .flatMap({ ($0 as? NSDictionary)?[dateID] }) else { return nil }
        if let raw = value as? String { return SwapStatus(rawValue: raw) }
        // Entries written before status tracking stored a Bool.
        return (value as? Bool) == true ? .succeeded : nil
    }
    
    // MARK: - Invoice description
    
    static func storeInvoiceDescription(preimage:String, desc:String) {
        setKeyedCache(CacheKeys.invoiceDescriptions, preimage, to: desc)
    }
    
    static func getInvoiceDescription(preimage:String) -> String {
        return keyedCache(CacheKeys.invoiceDescriptions)[preimage] ?? ""
    }
    
    // MARK: - Transaction note
    
    static func storeTransactionNote(txid:String, note:String) {
        setKeyedCache(CacheKeys.transactionNotes, txid, to: note)
    }
    
    static func deleteTransactionNote(txid:String) {
        setKeyedCache(CacheKeys.transactionNotes, txid, to: nil)
    }

    static func getTransactionNote(txid:String) -> String {
        return keyedCache(CacheKeys.transactionNotes)[txid] ?? ""
    }
    
    // MARK: - Payment fees
    
    static func storePaymentFees(preimage:String, fees:Int) {
        setKeyedCache(CacheKeys.paymentFees, preimage, to: fees)
        Log.info("Lightning fees cached.")
    }
    
    static func getLightningFees(preimage:String) -> Int {
        return keyedCache(CacheKeys.paymentFees)[preimage] ?? 0
    }
    
    // MARK: - Mnemonic
    
    static func storeMnemonic(_ mnemonic:String) throws {
        
        // Make sure no foreign LDK Node data remains available when creating or restoring a wallet.
        // Foreign LDK Node data can never restore a channel, and may lead to loss of funds.
        try quarantineLightningStateBeforeSeedImport()
        
        // Store new or restored mnemonic.
        try persistSecret(mnemonic, account: EnvironmentConfig.cacheKey(for: "mnemonic"), label: "mnemonic", accessibility: .afterFirstUnlockThisDeviceOnly)
    }
    
    private static func quarantineLightningStateBeforeSeedImport() throws {
        
        guard try readSecretOrThrow(account: EnvironmentConfig.cacheKey(for: "mnemonic")) == nil else {
            // A mnemonic already exists on this device, or is unreadable. Don't touch anything.
            return
        }
        guard LightningStorage.hasLightningState() else {
            // There is no LDK Node data on this device. Nothing to quarantine.
            return
        }
        Log.info("Foreign LDK Node data found while importing a seed.")
        
        // Quarantine foreign LDK Node data.
        // If this fails somehow, prevent the creation or restoration of the wallet.
        try LightningStorage.quarantineLightningState()
        
        // Inform the user about the discovery of foreign LDK Node data.
        BitcoinManager.shared.didQuarantineForeignState = true
    }
    
    static func getMnemonic() -> String? {
        readSecret(account: EnvironmentConfig.cacheKey(for: "mnemonic"))
    }
    
    // MARK: - Pin

    // The PIN is stored as a salted SHA-256 record ("v1$<salt>$<digest>",
    // base64) so its raw value never sits anywhere at rest — people reuse
    // bank-card PINs, so disclosure matters beyond this app. Honest scope:
    // hashing cannot make a 4-8 digit PIN resistant to offline brute force
    // (the keyspace is tiny); the wipe-after-10 attempt counter is the real
    // guard, and the mnemonic — not the PIN — is the actual key material.
    // Legacy raw values (UserDefaults, or early Keychain builds) are
    // re-hashed by the launch migration; verifyPin also upgrades any
    // straggler on its next successful entry.
    static func storePin(pin:String) {
        writeSecret(hashedPinRecord(for: pin), account: EnvironmentConfig.cacheKey(for: "pin"), label: "pin", accessibility: .whenUnlockedThisDeviceOnly)
    }

    /// Whether a PIN is stored (hashed or legacy raw).
    static func hasPin() -> Bool {
        readSecret(account: EnvironmentConfig.cacheKey(for: "pin")) != nil
    }

    /// Check an entered PIN against the stored record.
    static func verifyPin(_ entered: String) -> Bool {
        guard let stored = readSecret(account: EnvironmentConfig.cacheKey(for: "pin")) else { return false }
        if let record = parseHashedPinRecord(stored) {
            return pinDigest(entered, salt: record.salt) == record.digest
        }
        // Legacy raw value — compare directly, and upgrade to the hashed form
        // now that the correct PIN is known.
        guard stored == entered else { return false }
        storePin(pin: entered)
        return true
    }

    private static func hashedPinRecord(for pin: String) -> String {
        var salt = Data(count: 32)
        _ = salt.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 32, $0.baseAddress!) }
        return "v1$\(salt.base64EncodedString())$\(pinDigest(pin, salt: salt).base64EncodedString())"
    }

    private static func parseHashedPinRecord(_ record: String) -> (salt: Data, digest: Data)? {
        let parts = record.split(separator: "$")
        guard parts.count == 3, parts[0] == "v1",
              let salt = Data(base64Encoded: String(parts[1])),
              let digest = Data(base64Encoded: String(parts[2])) else { return nil }
        return (salt, digest)
    }

    private static func pinDigest(_ pin: String, salt: Data) -> Data {
        var input = salt
        input.append(Data(pin.utf8))
        return Data(SHA256.hash(data: input))
    }
    
    // MARK: - Secure storage (Keychain)
    
    // Check whether PIN and mnemonic are available.
    enum WalletSecretsPresence {
        case present
        case absent
        case unavailable
    }
    
    static func walletSecretsPresence() -> WalletSecretsPresence {
        // While the device is locked the WhenUnlockedThisDeviceOnly items are
        // unreadable, so we can't decide anything.
        guard UIApplication.shared.isProtectedDataAvailable else { return .unavailable }
        do {
            let mnemonic = try readSecretOrThrow(account: EnvironmentConfig.cacheKey(for: "mnemonic"))
            let pin = try readSecretOrThrow(account: EnvironmentConfig.cacheKey(for: "pin"))
            return (mnemonic != nil && pin != nil) ? .present : .absent
        } catch {
            // A Keychain read failed (not a genuine absence). Report it and treat
            // as unavailable so nothing destructive happens.
            SentryManager.capture(error, context: "reading wallet secrets for presence check")
            return .unavailable
        }
    }

    /// Eagerly migrate any legacy UserDefaults-stored secrets (mnemonic, PIN,
    /// and an in-flight swap's refund key) into the Keychain. Safe to call on
    /// every launch; a no-op once migrated.
    static func migrateSecretsToKeychainIfNeeded() {
        migrateLegacyValue(account: EnvironmentConfig.cacheKey(for: "mnemonic"), accessibility: .afterFirstUnlockThisDeviceOnly)
        migrateLegacyValue(account: EnvironmentConfig.cacheKey(for: "pin"), accessibility: .whenUnlockedThisDeviceOnly)
        migrateLegacyOngoingSwapKey()
        applyProtectionToExistingSwapFiles()
        // Items keep the accessibility class they were written with; the
        // mnemonic's intended class changed (WhenUnlocked -> AfterFirstUnlock,
        // so background node starts work) after the first Keychain builds.
        // Rewriting in place re-applies the intended class; idempotent.
        refreshAccessibility(account: EnvironmentConfig.cacheKey(for: "mnemonic"), accessibility: .afterFirstUnlockThisDeviceOnly)
        refreshAccessibility(account: EnvironmentConfig.cacheKey(for: "pin"), accessibility: .whenUnlockedThisDeviceOnly)
        // Re-hash a legacy raw PIN (from UserDefaults, or an early Keychain
        // build that stored the raw value).
        if let storedPin = (try? SecureStore.getString(account: EnvironmentConfig.cacheKey(for: "pin"))) ?? nil, parseHashedPinRecord(storedPin) == nil {
            storePin(pin: storedPin)
        }
    }

    /// Re-apply the intended accessibility class to an already-stored secret
    /// by rewriting it in place. No-op when nothing is stored.
    private static func refreshAccessibility(account: String, accessibility: SecureStore.Accessibility) {
        guard let value = (try? SecureStore.getString(account: account)) ?? nil else { return }
        try? SecureStore.setString(value, account: account, accessibility: accessibility)
    }

    /// Stamp existing swap JSON files with the at-rest protection class that
    /// new writes get explicitly (saveSwapDetailsToFile). Files are only ever
    /// rewritten while a swap is in flight, so completed swaps' files would
    /// otherwise keep whatever class they were created with. Idempotent and
    /// content-preserving: this sets a file attribute — the file's deliberate
    /// plain-text content (the Boltz rescue artifact) is untouched.
    private static func applyProtectionToExistingSwapFiles() {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        guard let files = try? FileManager.default.contentsOfDirectory(at: documentsPath, includingPropertiesForKeys: nil) else { return }
        for file in files where file.pathExtension == "json" {
            try? FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: file.path
            )
        }
    }

    /// Move a legacy ongoingswap dictionary's inline Boltz refund key into the
    /// Keychain. Same contract as migrateLegacyValue: the UserDefaults copy is
    /// only stripped once the Keychain copy is confirmed readable, so access
    /// is never lost. Idempotent.
    private static func migrateLegacyOngoingSwapKey() {
        guard let storedSwap = CacheStore.plistObject(for: CacheKeys.ongoingSwap) as? NSDictionary,
              let privateKey = storedSwap["privateKey"] as? String,
              let boltzID = storedSwap["boltzID"] as? String else {
            return
        }
        if storeSwapPrivateKey(privateKey, boltzID: boltzID), let stripped = storedSwap.mutableCopy() as? NSMutableDictionary {
            stripped.removeObject(forKey: "privateKey")
            CacheStore.setPlistObject(stripped, for: CacheKeys.ongoingSwap)
        }
    }

    /// Write a secret to the Keychain and confirm it by reading it back. Throws
    /// if the write fails or the read-back doesn't match, so callers that must
    /// not proceed without the secret persisted (wallet creation/restore) can
    /// fail loudly instead of stranding a wallet whose seed was never saved.
    private static func persistSecret(_ value: String, account: String, label: String, accessibility: SecureStore.Accessibility) throws {
        do {
            try SecureStore.setString(value, account: account, accessibility: accessibility)
            let readBack = (try? SecureStore.getString(account: account)) ?? nil
            guard readBack == value else {
                throw SecureStore.SecureStoreError.writeVerificationFailed
            }
        } catch {
            SentryManager.capture(error, context: "storing \(label) in keychain")
            throw error
        }
    }

    /// Non-throwing convenience for secrets where a failed write is recoverable
    /// (e.g. the PIN, which can be reset via the mnemonic). Failures are logged.
    private static func writeSecret(_ value: String, account: String, label: String, accessibility: SecureStore.Accessibility) {
        try? persistSecret(value, account: account, label: label, accessibility: accessibility)
    }

    /// Non-throwing read used by getMnemonic()/getPin(). A Keychain read failure
    /// yields nil here (existing callers guard on nil and handle it gracefully);
    /// it never drives a destructive decision — the launch presence check uses
    /// walletSecretsPresence() instead, which separates failure from absence.
    /// The intended accessibility class for a secret, by account. The
    /// mnemonic (and swap keys) must be readable in background wakes; the PIN
    /// is foreground-only. See SecureStore's header.
    private static func accessibilityForAccount(_ account: String) -> SecureStore.Accessibility {
        return account == EnvironmentConfig.cacheKey(for: "pin") ? .whenUnlockedThisDeviceOnly : .afterFirstUnlockThisDeviceOnly
    }

    private static func readSecret(account: String) -> String? {
        do {
            return try readSecretOrThrow(account: account)
        } catch {
            // Keychain read failed — still honour a legacy UserDefaults copy if one exists.
            return migrateLegacyValue(account: account, accessibility: accessibilityForAccount(account))
        }
    }

    /// Read a secret, throwing on a Keychain read failure and returning nil only
    /// when the value is genuinely absent (checked in the Keychain and in a
    /// legacy UserDefaults copy). Migrates a legacy value on the way.
    private static func readSecretOrThrow(account: String) throws -> String? {
        if let value = try SecureStore.getString(account: account) {
            UserDefaults.standard.removeObject(forKey: account)   // clean up any legacy leftover
            return value
        }
        return migrateLegacyValue(account: account, accessibility: accessibilityForAccount(account))
    }

    /// Move a legacy UserDefaults value into the Keychain (if one exists). Returns
    /// the value so a read still works even if the Keychain write can't complete
    /// right now; the UserDefaults copy is removed only once the Keychain copy is
    /// confirmed readable, so access is never lost. Idempotent.
    @discardableResult
    private static func migrateLegacyValue(account: String, accessibility: SecureStore.Accessibility) -> String? {
        guard let legacy = UserDefaults.standard.value(forKey: account) as? String else {
            return nil
        }
        do {
            try SecureStore.setString(legacy, account: account, accessibility: accessibility)
            let confirmed = (try? SecureStore.getString(account: account)) ?? nil
            if confirmed == legacy {
                UserDefaults.standard.removeObject(forKey: account)   // safe: verified in Keychain
            }
        } catch {
            // Keychain write failed — keep the UserDefaults copy so access isn't lost.
            SentryManager.capture(error, context: "migrating secret to keychain")
        }
        return legacy
    }
    
    // MARK: - Txo ID
    
    static func storeTxoID(txoID:String) {
        CacheStore.set(txoID, for: CacheKeys.txoID)
    }
    
    static func getTxoID() -> String? {
        return CacheStore.value(for: CacheKeys.txoID)
    }
    
    // MARK: - Channel funding outpoint
    
    // Store a channel's funding output.
    // Upon a cooperative close, we can deduce the onchain transaction from this output.
    static func storeChannelFundingOutpoint(txID:String, vout:UInt32) {
        CacheStore.encode(ChannelOutpoint(txID: txID, vout: vout), for: CacheKeys.channelFundingOutpoint)
    }
    
    // Drop the outpoint once its closing transaction has been found.
    static func removeChannelFundingOutpoint() {
        CacheStore.remove(CacheKeys.channelFundingOutpoint)
    }
    
    static func getChannelFundingOutpoint() -> ChannelOutpoint? {
        return CacheStore.decoded(for: CacheKeys.channelFundingOutpoint, migratingLegacyWith: legacyChannelOutpoint)
    }
    
    // MARK: - Channel closure transactions
    
    static func storeChannelClosureTxIDs(txIDs:[String]) {
        let cachedTxIDs = getChannelClosureTxIDs()
        let newTxIDs = txIDs.filter { !cachedTxIDs.contains($0) }
        guard !newTxIDs.isEmpty else { return }
        CacheStore.set(cachedTxIDs + newTxIDs, for: CacheKeys.channelClosureTxIDs)
    }
    
    static func getChannelClosureTxIDs() -> [String] {
        return CacheStore.value(for: CacheKeys.channelClosureTxIDs) ?? []
    }
    
    // MARK: - Sent to Bittr
    
    static func updateSentToBittr(txids:[String]) {
        let cached = getSentToBittr()
        let newTxIDs = txids.filter { !cached.contains($0) }
        guard !newTxIDs.isEmpty else { return }
        CacheStore.set(cached + newTxIDs, for: CacheKeys.sentToBittr)
    }
    
    static func getSentToBittr() -> [String] {
        return CacheStore.value(for: CacheKeys.sentToBittr) ?? []
    }
    
    // MARK: - Last address
    
    static func storeLastAddress(newAddress:String) {
        CacheStore.set(newAddress, for: CacheKeys.lastAddress)
    }
    
    static func getLastAddress() -> String? {
        return CacheStore.value(for: CacheKeys.lastAddress)
    }
    
    // MARK: - Failed pin attempts
    
    // The wipe-after-10 counter lives in the Keychain, not UserDefaults:
    // backups restore UserDefaults but a live device's Keychain kept the PIN,
    // so a backup-restore cycle used to reset the counter while the PIN
    // survived — unlimited attempts for anyone with backup access. Honest
    // scope: a full same-device erase-and-restore replays ThisDeviceOnly
    // items too and buys another 9 attempts per multi-minute cycle; the
    // Keychain counter turns a seconds-long plist edit into that, it does
    // not eliminate it. Reads fail open (0): wiping wallets on a transient
    // Keychain error would be worse than granting extra attempts.
    private static var failedAttemptsAccount: String {
        EnvironmentConfig.cacheKey(for: "failedattempts")
    }

    static func getFailedPinAttempts() -> Int {
        migrateLegacyFailedAttemptsIfNeeded()
        guard let stored = (try? SecureStore.getString(account: failedAttemptsAccount)) ?? nil else { return 0 }
        return Int(stored) ?? 0
    }

    static func increaseFailedPinAttempts() {
        let next = getFailedPinAttempts() + 1
        try? SecureStore.setString("\(next)", account: failedAttemptsAccount, accessibility: .whenUnlockedThisDeviceOnly)
    }

    static func resetFailedPinAttempts() {
        SecureStore.remove(account: failedAttemptsAccount)
        UserDefaults.standard.removeObject(forKey: failedAttemptsAccount)
    }

    /// Move a legacy UserDefaults counter into the Keychain. Keeps the higher
    /// of the two values so a restored (older) count can never lower a live
    /// one. Idempotent; the UserDefaults copy is removed once read.
    private static func migrateLegacyFailedAttemptsIfNeeded() {
        guard let legacy = UserDefaults.standard.value(forKey: failedAttemptsAccount) as? Int else { return }
        let current = Int(((try? SecureStore.getString(account: failedAttemptsAccount)) ?? nil) ?? "0") ?? 0
        if legacy > current {
            try? SecureStore.setString("\(legacy)", account: failedAttemptsAccount, accessibility: .whenUnlockedThisDeviceOnly)
        }
        UserDefaults.standard.removeObject(forKey: failedAttemptsAccount)
    }

    // MARK: - Wallet removal in progress

    static func setWalletRemovalInProgress(_ inProgress: Bool) {
        CacheStore.set(inProgress, for: CacheKeys.walletRemovalInProgress)
    }

    static func walletRemovalIsInProgress() -> Bool {
        return CacheStore.value(for: CacheKeys.walletRemovalInProgress) ?? false
    }

    // MARK: - Event handling
    
    static func didHandleEvent(event:String) {
        var handledEvents = CacheStore.value(for: CacheKeys.handledEvents) ?? []
        guard !handledEvents.contains(event) else { return }
        handledEvents += [event]
        CacheStore.set(handledEvents, for: CacheKeys.handledEvents)
    }
    
    static func hasHandledEvent(event:String) -> Bool {
        return (CacheStore.value(for: CacheKeys.handledEvents) ?? []).contains(event)
    }
    
    // MARK: - Dark mode
    
    static func setCurrentDarkMode(darkModeIsOn:Bool) {
        CacheStore.set(darkModeIsOn ? "dark" : "light", for: CacheKeys.currentDarkMode)
    }
    
    static func darkModeIsOn() -> Bool {
        return CacheStore.value(for: CacheKeys.currentDarkMode) == "dark"
    }
    
    static func updateDarkMode(_ setting:DarkMode) {
        CacheStore.set(setting.rawValue, for: CacheKeys.darkModeSetting)
    }
    
    static func darkMode() -> DarkMode {
        guard let stored = CacheStore.value(for: CacheKeys.darkModeSetting) else { return .device }
        return DarkMode(rawValue: stored) ?? .device
    }
    
    // MARK: - Language settings
    
    static func getLanguage() -> String {
        return CacheStore.value(for: CacheKeys.language) ?? "en_US"
    }
    
    static func changeLanguage(_ toLanguage:String) {
        CacheStore.set(toLanguage, for: CacheKeys.language)
        NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "changecolors"), object: nil, userInfo: nil) as Notification)
    }
    
    // MARK: - Swaps
    
    static func saveLatestSwap(_ latestSwap:Swap?) {

        if let swap = latestSwap, let swapDictionary = swap.toDictionary().mutableCopy() as? NSMutableDictionary {
            // Keep the Boltz refund key out of UserDefaults: store it in the
            // Keychain (keyed per swap) and strip it from the persisted
            // dictionary — but only once the Keychain copy is confirmed
            // readable. If the write fails, the key stays inline: for an
            // in-flight swap, a plaintext key beats a lost refund key.
            // (The per-swap JSON file DELIBERATELY keeps the key in plain
            // text — it is the user-facing emergency artifact for Boltz's
            // rescue flow and must not depend on a working app or Keychain.)
            if let privateKey = swap.privateKey, let boltzID = swap.boltzID, storeSwapPrivateKey(privateKey, boltzID: boltzID) {
                swapDictionary.removeObject(forKey: "privateKey")
            }
            CacheStore.setPlistObject(swapDictionary, for: CacheKeys.ongoingSwap)
        } else {
            if let storedSwap = CacheStore.plistObject(for: CacheKeys.ongoingSwap) as? NSDictionary, let boltzID = storedSwap["boltzID"] as? String {
                SecureStore.remove(account: "swapkey_\(boltzID)")
            }
            CacheStore.remove(CacheKeys.ongoingSwap)
        }
    }

    static func getLatestSwap() -> Swap? {
        if let storedSwap = CacheStore.plistObject(for: CacheKeys.ongoingSwap) as? NSDictionary {
            let thisSwap = storedSwap.toSwap()
            // New saves strip the refund key from the dictionary — read it
            // back from the Keychain. A legacy dictionary still carries it
            // inline (toSwap picks that up), and
            // migrateSecretsToKeychainIfNeeded moves it across on launch.
            if thisSwap.privateKey == nil, let boltzID = thisSwap.boltzID {
                thisSwap.privateKey = (try? SecureStore.getString(account: "swapkey_\(boltzID)")) ?? nil
            }
            return thisSwap
        } else {
            return nil
        }
    }

    /// Store an in-flight swap's Boltz refund key in the Keychain, verified by
    /// read-back. Returns true only when the Keychain copy is confirmed, so
    /// callers only strip the inline copy on certainty.
    private static func storeSwapPrivateKey(_ privateKey: String, boltzID: String) -> Bool {
        do {
            try SecureStore.setString(privateKey, account: "swapkey_\(boltzID)", accessibility: .afterFirstUnlockThisDeviceOnly)
            guard ((try? SecureStore.getString(account: "swapkey_\(boltzID)")) ?? nil) == privateKey else {
                throw SecureStore.SecureStoreError.writeVerificationFailed
            }
            return true
        } catch {
            SentryManager.capture(error, context: "storing swap private key in keychain")
            return false
        }
    }
    
    // MARK: - Swap Index Cache
    
    static func getSwapIndex() -> Int {
        guard let cached = CacheStore.value(for: CacheKeys.swapIndex) else {
            CacheStore.set(0, for: CacheKeys.swapIndex)
            return 0
        }
        return cached
    }
    
    static func incrementSwapIndex() -> Int {
        let newIndex = getSwapIndex() + 1
        CacheStore.set(newIndex, for: CacheKeys.swapIndex)
        return newIndex
    }
    
    static func resetSwapIndex() {
        CacheStore.set(0, for: CacheKeys.swapIndex)
    }
    
    static func getCurrentSwapIndex() -> Int {
        return getSwapIndex()
    }
    
    // MARK: - Academy cache
    
    static func addCompletedLesson(_ lessonId:String) {
        var completedLessons = getCompletedLessons()
        guard !completedLessons.contains(lessonId) else { return }
        completedLessons += [lessonId]
        CacheStore.set(completedLessons, for: CacheKeys.completedLessons)
    }
    
    static func getCompletedLessons() -> [String] {
        return CacheStore.value(for: CacheKeys.completedLessons) ?? []
    }
    
    // MARK: - Onchain addresses
    
    static func getOnchainAddresses() -> [OnchainAddress] {
        let cached = CacheStore.decoded(for: CacheKeys.onchainAddresses, migratingLegacyWith: legacyOnchainAddresses)
        return (cached ?? []).inPoolOrder()
    }
    
    static func storeOnchainAddresses(_ theseAddresses:[OnchainAddress]) {
        CacheStore.encode(theseAddresses, for: CacheKeys.onchainAddresses)
    }
    
}
