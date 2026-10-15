//
//  BDKManager.swift
//  bittr
//
//  Created by Tom Melters on 2/6/26.
//

import Foundation
import BitcoinDevKit

struct OnchainDrainPreview {
    let sendableSats:UInt64
    let feeSats:UInt64
    let vsize:UInt64
}

enum LightSyncOutcome {
    case synced
    case skippedForFullScan
    case skippedForLightSync
    case failed
}

struct LightSyncClaim {
    let id = UUID()
    let startedAt = Date()
    
    // The previous light sync held the claim for too long, so its Electrum connection may be stuck.
    let replacesHungSync:Bool
}

final class BdkScanState {
    
    private let lock = NSLock()
    private var _isScanning = false
    private var _hasBeenScanned = false
    private var _timedOut = false
    private var _lightSync:LightSyncClaim?
    private var waiters = [(Bool) -> Void]()
    
    var isScanning: Bool {
        // A full scan is running right now.
        lock.lock()
        defer { lock.unlock() }
        return _isScanning
    }
    
    var hasBeenScanned: Bool {
        // A full scan has finished at least once since launch.
        lock.lock()
        defer { lock.unlock() }
        return _hasBeenScanned
    }
    
    var timedOut: Bool {
        // The running scan passed its watchdog.
        lock.lock()
        defer { lock.unlock() }
        return _timedOut
    }
    
    func claim(orWaitWith waiter: @escaping (Bool) -> Void) -> Bool {
        // Claims the right to run a full scan.
        lock.lock()
        defer { lock.unlock() }

        if _isScanning {
            waiters += [waiter]
            return false
        }
        _isScanning = true
        _timedOut = false
        return true
    }
    
    func end(scanned: Bool) {
        // Releases the claim and hands the outcome to whoever was waiting on it.
        lock.lock()
        _isScanning = false
        if scanned { _hasBeenScanned = true }
        let waiting = waiters
        waiters.removeAll()
        lock.unlock()

        guard !waiting.isEmpty else { return }
        DispatchQueue.main.async { waiting.forEach { $0(scanned) } }
    }

    // How long a light sync may hold its claim before it counts as hung.
    static let lightSyncClaimLimit:TimeInterval = 120
    
    func claimLightSync() -> LightSyncClaim? {
        // Claims the right to run a light sync, taking over from one that has hung.
        lock.lock()
        defer { lock.unlock() }
        
        if let current = _lightSync, Date().timeIntervalSince(current.startedAt) < BdkScanState.lightSyncClaimLimit {
            return nil
        }
        let claim = LightSyncClaim(replacesHungSync: _lightSync != nil)
        _lightSync = claim
        return claim
    }
    
    func endLightSync(_ claim:LightSyncClaim) {
        // Releases the claim, unless a newer light sync has taken it over.
        lock.lock()
        defer { lock.unlock() }
        guard _lightSync?.id == claim.id else { return }
        _lightSync = nil
    }
    
    func markPreviouslyScanned() {
        lock.lock()
        defer { lock.unlock() }
        _hasBeenScanned = true
    }
    
    func markNeedsFullScan() {
        lock.lock()
        defer { lock.unlock() }
        _hasBeenScanned = false
    }
    
    func markTimedOut() {
        // The watchdog fired.
        lock.lock()
        defer { lock.unlock() }
        guard _isScanning else { return }
        _timedOut = true
    }

    func clear() {
        // Forgets all of it.
        lock.lock()
        _isScanning = false
        _hasBeenScanned = false
        _timedOut = false
        let waiting = waiters
        waiters.removeAll()
        lock.unlock()

        guard !waiting.isEmpty else { return }
        DispatchQueue.main.async { waiting.forEach { $0(false) } }
    }
}

extension BitcoinManager {
    
    func didStartBDK() -> Bool {
        
        // One start at a time.
        self.bdkStartLock.lock()
        defer { self.bdkStartLock.unlock() }
        
        guard self.bdkWallet == nil else {
            return true
        }
        Log.info("Will start blockchain and wallet.")
        
        // Check mnemonic.
        guard let cachedMnemonic = CacheManager.getMnemonic() else {
            Log.info("No mnemonic in cache; wallet is being torn down. Aborting BDK start.")
            return false
        }

        // Attempt to create a mnemonic object from the provided mnemonic string.
        let mnemonic:BitcoinDevKit.Mnemonic
        do {
            mnemonic = try BitcoinDevKit.Mnemonic.fromString(mnemonic: cachedMnemonic)
        } catch {
            self.handleError(error: error, row: 178)
            return false
        }
        
        // Create a BIP32 extended root key using the mnemonic and a nil password
        let bip32ExtendedRootKey = DescriptorSecretKey(network: EnvironmentConfig.bitcoinDevKitNetwork, mnemonic: mnemonic, password: nil)
        
        // Create a BIP84 external descriptor using the BIP32 extended root key, specifying the keychain as external and the network as testnet
        let bip84ExternalDescriptor = Descriptor.newBip84(secretKey: bip32ExtendedRootKey, keychain: .external, network: EnvironmentConfig.bitcoinDevKitNetwork)
        
        // Get XPUB.
        let descriptor = bip84ExternalDescriptor.description
        let components = descriptor.components(separatedBy: "]")
        if components.count > 1 {
            let xpubPart = components[1].split(separator: "/").first
            if let xpub = xpubPart {
                self.xpub = String(xpub)
            } else {
                Log.info("Error: Could not extract XPUB")
            }
        } else {
            Log.info("Error: Descriptor format not recognized")
        }
        
        // Create a BIP84 internal descriptor using the same BIP32 extended root key, specifying the keychain as internal and the network as testnet
        let bip84InternalDescriptor = Descriptor.newBip84(secretKey: bip32ExtendedRootKey, keychain: .internal, network: EnvironmentConfig.bitcoinDevKitNetwork)
        
        // Open the stored wallet database, or an empty one when the user asked for a rebuild.
        do {
            if self.bdkRebuildIsRequested {
                Log.info("A BDK rebuild was requested. Will start from an empty database.")
                self.connection = try Connection.recreate()
            } else {
                self.connection = try Connection.open()
            }
        } catch where error.isCorruptDatabase {
            self.handleError(error: error, row: 211)
            
            // A corrupt database holds nothing worth keeping, so start an empty one.
            self.clearFullScanCompletion()
            do {
                self.connection = try Connection.recreate()
            } catch {
                self.handleError(error: error, row: 214)
                self.clearBdkWalletReferences()
                return false
            }
        } catch {
            // Anything else may pass, so leave the file for the next launch to try again.
            self.handleError(error: error, row: 213)
            self.clearBdkWalletReferences()
            return false
        }
        
        do {
            // Check whether a stored BDK wallet is available.
            let loaded = try Wallet.load(descriptor: bip84ExternalDescriptor, changeDescriptor: bip84InternalDescriptor, connection: self.connection!)
            
            // Confirm the stored wallet's network matches this build's network.
            guard loaded.network() == EnvironmentConfig.bitcoinDevKitNetwork else {
                throw WalletError.storedWalletOnAnotherNetwork
            }
            
            Log.info("Did load the stored BDK wallet.")
            SentryManager.countMetric("sync.bdk.loaded")
            self.bdkWallet = loaded
            
            if self.hasStoredFullScan {
                Log.info("A full scan is stored. Will light sync rather than scan.")
                SentryManager.countMetric("sync.bdk.scan.skipped")
            } else {
                Log.info("No stored full scan is available. Will scan.")
            }
        } catch {
            // Only replace a database that is corrupt, or doesn't hold this wallet.
            let reason:String? = {
                switch error {
                case LoadWithPersistError.CouldNotLoad: return "nothing stored"
                case LoadWithPersistError.InvalidChangeSet: return "stored data did not match"
                case WalletError.storedWalletOnAnotherNetwork: return "stored on another network"
                case _ where error.isCorruptDatabase: return "database is corrupt"
                default: return nil
                }
            }()
            
            guard let reason else {
                // A read failure may pass, so keep the file for the next launch to try again.
                self.handleError(error: error, row: 216)
                self.clearBdkWalletReferences()
                return false
            }
            Log.info("No stored BDK wallet to load (\(reason)). Creating one.")
            SentryManager.countMetric("sync.bdk.recreated")
            
            // Release the database before deleting the file underneath it.
            self.connection = nil
            self.clearFullScanCompletion()
            
            do {
                self.connection = try Connection.recreate()
                self.bdkWallet = try Wallet(descriptor: bip84ExternalDescriptor, changeDescriptor: bip84InternalDescriptor, network: EnvironmentConfig.bitcoinDevKitNetwork, connection: self.connection!)
                
                // A new wallet has revealed nothing, so reveal the cached address pool again for syncs to watch.
                if let topIndex = CacheManager.getOnchainAddresses().map(\.addressIndex).max() {
                    // Reveal a little beyond the pool too, like manageOnchainAddresses does for channel closures.
                    self.revealAddresses(toIndex: topIndex + 5)
                }
                
                // The wallet has been built from scratch, so a requested rebuild is done.
                self.clearBdkRebuildRequest()
            } catch {
                self.handleError(error: error, row: 218)
                self.clearBdkWalletReferences()
                return false
            }
        }
        
        // Configure and create an Electrum blockchain connection to interact with the Bitcoin network
        do {
            self.electrumClient = try ElectrumClient(url: EnvironmentConfig.electrumURL)
        } catch {
            self.handleError(error: error, row: 228)
            self.clearBdkWalletReferences()
            return false
        }
        
        Log.info("Did initiate wallet and blockchain.")
        SentryManager.countMetric("sync.bdk.success")
        return true
    }
    
    private func clearBdkWalletReferences() {
        // Leave nothing half-built behind after a failed start.
        self.bdkWallet = nil
        self.electrumClient = nil
        self.connection = nil
    }
    
    // MARK: Manage BDK scanning.
    
    var bdkWalletIsScanning: Bool { self.bdkScan.isScanning }
    var bdkWalletHasBeenScanned: Bool { self.bdkScan.hasBeenScanned }
    var bdkFullScanTimedOut: Bool { self.bdkScan.timedOut }

    func claimBdkScan(orWaitWith waiter: @escaping (Bool) -> Void) -> Bool {
        return self.bdkScan.claim(orWaitWith: waiter)
    }
    func endBdkScan(scanned: Bool) {
        self.bdkScan.end(scanned: scanned)
    }
    func markBdkScanTimedOut() {
        self.bdkScan.markTimedOut()
    }
    func clearBdkScanState() {
        self.bdkScan.clear()
    }
    func markBdkNeedsRebuild() {
        self.bdkScan.markNeedsFullScan()
        
        // Remember the request, so the next launch still rebuilds the wallet if this session doesn't.
        CacheStore.set(true, for: CacheKeys.bdkRebuildRequested)
        
        // Forget the last full scan, so the next launch still scans if this one doesn't finish.
        self.clearFullScanCompletion()
    }
    var bdkRebuildIsRequested: Bool {
        return CacheStore.value(for: CacheKeys.bdkRebuildRequested) == true
    }
    func clearBdkRebuildRequest() {
        CacheStore.set(nil, for: CacheKeys.bdkRebuildRequested)
    }
    
    // Throw the loaded BDK wallet away and build it again from an empty database.
    private func didRebuildBdkWallet() -> Bool {
        Log.info("Will rebuild the BDK wallet.")
        
        // Wait for a running light sync to finish, as it still writes to the stored database.
        let deadline = Date().addingTimeInterval(30)
        var lightSyncClaim = self.bdkScan.claimLightSync()
        while lightSyncClaim == nil, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.25)
            lightSyncClaim = self.bdkScan.claimLightSync()
        }
        guard let lightSyncClaim else {
            Log.info("A light sync is still running. Will rebuild the BDK wallet later.")
            return false
        }
        defer { self.bdkScan.endLightSync(lightSyncClaim) }
        
        // Release the loaded wallet, so didStartBDK builds a new one.
        self.bdkStartLock.lock()
        self.bdkWallet = nil
        self.connection = nil
        self.bdkStartLock.unlock()
        
        return self.didStartBDK()
    }
    func markBdkPreviouslyScanned() {
        self.bdkScan.markPreviouslyScanned()
    }
    
    // A full scan stands until the user asks for another one by pulling to refresh.
    var hasStoredFullScan: Bool {
        // Check when the BDK wallet was last scanned.
        guard let scannedAt = CacheStore.value(for: CacheKeys.lastBdkFullScan) else { return false }
        
        // Make sure the cached most recent scan date is after this database's creation date.
        guard let databaseCreated = Connection.walletDatabaseCreationDate else { return false }
        
        // The scan date is stored in whole seconds, so compare the creation date in whole seconds too.
        return Int(databaseCreated.timeIntervalSince1970) <= scannedAt
    }
    
    // Keep track of latest full BDK scan.
    func storeFullScanCompletion() {
        CacheStore.set(Int(Date().timeIntervalSince1970), for: CacheKeys.lastBdkFullScan)
    }
    func clearFullScanCompletion() {
        CacheStore.set(nil, for: CacheKeys.lastBdkFullScan)
    }
    
    func didSyncBdkWallet(completion originalCompletion: @escaping (Bool) -> Void) {
        
        // Handle sync completion.
        var didComplete = false
        func completion(_ success: Bool) {
            DispatchQueue.main.async {
                guard !didComplete else { return }
                didComplete = true
                originalCompletion(success)
            }
        }
        
        // Take the scan, or wait on the one already running.
        guard self.claimBdkScan(orWaitWith: completion) else {
            Log.info("A BDK full scan is already running. Waiting on it.")
            return
        }
        Log.info("Will sync BDK wallet.")
        
        // TODO: Consider a higher timeout limit for mainnet wallets.
        DispatchQueue.global(qos: .background).asyncAfter(deadline: .now() + 180) {
            Log.info("BDK full scan timed out after 180s; failing so callers don't hang.")
            self.markBdkScanTimedOut()
            completion(false)
        }
        
        DispatchQueue.global(qos: .background).async {
            // Rebuild the wallet first when the user asked for it.
            if self.bdkRebuildIsRequested {
                guard self.didRebuildBdkWallet() else {
                    self.endBdkScan(scanned: false)
                    completion(false)
                    return
                }
            }
            
            // Get Electrum Client.
            if self.electrumClient == nil {
                do {
                    self.electrumClient = try ElectrumClient(url: EnvironmentConfig.electrumURL)
                } catch {
                    self.handleError(error: error, row: 222)
                    self.endBdkScan(scanned: false)
                    completion(false)
                    return
                }
            }
            
            // Bind references locally.
            guard let bdkWallet = self.bdkWallet,
                  let electrumClient = self.electrumClient,
                  let connection = self.connection else {
                self.endBdkScan(scanned: false)
                completion(false)
                return
            }
            Log.info("Will perform a full scan.")
            
            // Build request.
            let syncRequest:FullScanRequest
            do {
                syncRequest = try bdkWallet.startFullScan().build()
            } catch {
                self.handleError(error: error, row: 212)
                self.endBdkScan(scanned: false)
                completion(false)
                return
            }
            
            // Run full scan.
            let update:Update
            do {
                update = try electrumClient.fullScan(
                    request: syncRequest,
                    stopGap: UInt64(25),
                    batchSize: UInt64(25),
                    fetchPrevTxouts: true
                )
            } catch {
                self.handleError(error: error, row: 236)
                self.endBdkScan(scanned: false)
                completion(false)
                return
            }
            
            // Ensure bdkWallet still exists.
            guard self.bdkWallet === bdkWallet else {
                self.endBdkScan(scanned: false)
                completion(false)
                return
            }
            
            // Apply update to BDK wallet.
            do {
                try bdkWallet.applyUpdate(update: update)
            } catch {
                self.handleError(error: error, row: 243)
                self.endBdkScan(scanned: false)
                completion(false)
                return
            }
            
            // Persist wallet changes, and only then count the full scan as done.
            do {
                let _ = try bdkWallet.persist(connection: connection)
                self.storeFullScanCompletion()
            } catch {
                self.handleError(error: error, row: 250)
                
                // The stored data lacks this scan, so the next launch must scan again.
                self.clearFullScanCompletion()
            }
            
            // Update syncing status.
            Log.info("Did sync BDK wallet.")
            self.endBdkScan(scanned: true)
            self.storeChannelClosureTxIDIfFound()
            completion(true)
        }
    }
    
    func lightSyncBdkWallet() -> LightSyncOutcome {
        // Stand down while a full scan is running.
        guard !self.bdkWalletIsScanning else {
            Log.info("Skipping light sync — a BDK full scan is in progress.")
            return .skippedForFullScan
        }
        
        // One light sync at a time.
        guard let lightSyncClaim = self.bdkScan.claimLightSync() else {
            Log.info("Skipping light sync — another one is in progress.")
            return .skippedForLightSync
        }
        defer { self.bdkScan.endLightSync(lightSyncClaim) }
        
        // A hung light sync may have left the Electrum connection stuck, so open a new one.
        if lightSyncClaim.replacesHungSync {
            Log.info("A light sync has hung. Will reconnect to Electrum.")
            SentryManager.countMetric("sync.bdk.lightsync.hung")
            do {
                self.electrumClient = try ElectrumClient(url: EnvironmentConfig.electrumURL)
            } catch {
                self.handleError(error: error, row: 565)
                return .failed
            }
        }

        guard let bdkWallet = self.bdkWallet,
              let electrumClient = self.electrumClient,
              let connection = self.connection else {
            return .failed
        }
        
        // Create sync request.
        let syncRequest:SyncRequest
        do {
            syncRequest = try bdkWallet.startSyncWithRevealedSpks().build()
        } catch {
            self.handleError(error: error, row: 570)
            return .failed
        }
        
        // Create update.
        let update:Update
        do {
            update = try electrumClient.sync(
                request: syncRequest,
                batchSize: UInt64(25),
                fetchPrevTxouts: true
            )
        } catch {
            self.handleError(error: error, row: 582)
            return .failed
        }
        
        // Ensure bdkWallet hasn't been cleared in the meantime.
        guard self.bdkWallet === bdkWallet else {
            return .failed
        }
        
        // Apply update to wallet.
        do {
            try bdkWallet.applyUpdate(update: update)
        } catch {
            self.handleError(error: error, row: 594)
            return .failed
        }
        
        // Persist update to wallet.
        do {
            _ = try bdkWallet.persist(connection: connection)
        } catch {
            self.handleError(error: error, row: 603)
        }
        
        self.storeChannelClosureTxIDIfFound()
        
        return .synced
    }
    
    func getSize(address:String, amountSats:Int, selectedVbyte:Double?) throws -> UInt64 {
        
        let tx = try self.getTx(address: address, amountSats: amountSats, selectedVbyte: selectedVbyte)
        let size = tx.vsize()
        
        return size
    }
    
    // MARK: - Onchain maximum
    
    // Get a placeholder output script to calculate fees before knowing the recipient.
    static var largestCommonOutputScript: Script {
        Script(rawOutputScript: [0x51, 0x20] + [UInt8](repeating: 0, count: 32))
    }
    
    // Get maximum sendable onchain transaction.
    func previewOnchainDrain(toScript script:Script, satPerVb:UInt64) throws -> OnchainDrainPreview {
        guard let wallet = self.bdkWallet else {
            throw WalletError.walletNotInitiated
        }
        
        // Minimum 1 sat/vB.
        let feeRate = try FeeRate.fromSatPerVb(satVb: max(satPerVb, 1))
        
        let psbt = try TxBuilder()
            .drainWallet()
            .drainTo(script: script)
            .feeRate(feeRate: feeRate)
            .finish(wallet: wallet)
        let _ = try wallet.sign(psbt: psbt, signOptions: nil)
        let tx = try psbt.extractTx()
        
        // drainTo produces exactly one output, so its value is the maximum.
        guard let drainOutput = tx.output().first else {
            throw WalletError.drainProducedNoOutput
        }
        
        return OnchainDrainPreview(sendableSats: drainOutput.value, feeSats: try psbt.fee(), vsize: tx.vsize())
    }
    
    // Calculate the maximum sendable onchain amount, with or without known recipient.
    func maximumSendableOnchainDrain(toAddress address:String?, satPerVb:UInt64) throws -> OnchainDrainPreview {

        let script:Script
        if let address = address,
           let parsed = try? Address(address: address, network: EnvironmentConfig.bitcoinDevKitNetwork) {
            // Recipient is known.
            script = parsed.scriptPubkey()
        } else {
            // Recipient is unknown.
            script = BitcoinManager.largestCommonOutputScript
        }
        
        let preview = try self.previewOnchainDrain(toScript: script, satPerVb: satPerVb)
        
        // Verify that LDKNode agrees with BDK's maximum sendable onchain amount.
        // BDK knows nothing about the reserve LDK Node holds back for anchor
        // channels, so it will happily drain it; LDK's spendable balance is the
        // authority on what may actually leave.
        guard let loadedSpendable = BitcoinManager.shared.bittrWallet.satoshisOnchainSpendable else {
            // Balances haven't been read yet, so there's nothing to clamp
            // against. Note this is NOT the same as a spendable balance of zero,
            // which clamps to zero below.
            return preview
        }

        let spendable = UInt64(max(loadedSpendable, 0))
        guard preview.sendableSats + preview.feeSats > spendable else {
            // BDK is already at or under LDKNode's spendable balance, so it's
            // the more conservative of the two. Stick with it.
            return preview
        }
        let clamped = spendable > preview.feeSats ? spendable - preview.feeSats : 0
        return OnchainDrainPreview(sendableSats: clamped, feeSats: preview.feeSats, vsize: preview.vsize)
    }
    
    func maximumSendableOnchainSats(toAddress address:String?, satPerVb:UInt64) throws -> UInt64 {
        return try self.maximumSendableOnchainDrain(toAddress: address, satPerVb: satPerVb).sendableSats
    }
    
    func getTx(address:String, amountSats:Int, selectedVbyte:Double?) throws -> BitcoinDevKit.Transaction {
        
        let details = try self.getPsbt(address: address, amountSats: amountSats, selectedVbyte: selectedVbyte)
        let tx = try details.extractTx()
        
        return tx
    }
    
    func getPsbt(address:String, amountSats:Int, selectedVbyte:Double?) throws -> BitcoinDevKit.Psbt {
        
        guard self.bdkWallet != nil else {
            throw WalletError.walletNotInitiated
        }
        
        let network = EnvironmentConfig.bitcoinDevKitNetwork
        let address = try Address(address: address, network: network)
        let script = address.scriptPubkey()
        var txBuilder = TxBuilder().addRecipient(script: script, amount: BitcoinDevKit.Amount.fromSat(satoshi: UInt64(amountSats)))
        if let selectedVbyte = selectedVbyte {
            // Minimum 1 sat/Vbyte.
            txBuilder = txBuilder.feeRate(feeRate: try FeeRate.fromSatPerVb(satVb: selectedVbyte.wholeSatPerVb))
        }
        let details = try txBuilder.finish(wallet: self.bdkWallet!)
        let _ = try self.bdkWallet!.sign(psbt: details, signOptions: nil)
        
        return details
    }
    
    func isValidMnemonic(_ thisMnemonic:String) -> Bool {
        do {
            _ = try BitcoinDevKit.Mnemonic.fromString(mnemonic: thisMnemonic)
            return true
        } catch {
            // Could not generate mnemonic.
            return false
        }
    }
    
    // Look for the transaction that closed a channel and remember it.
    func storeChannelClosureTxIDIfFound() {
        
        // Nothing to look for until a channel has closed.
        let openFundingTxIDs = self.listChannels().compactMap { $0.fundingTxo?.txid }
        guard let fundingOutpoint = CacheManager.getChannelFundingOutpoint(),
              !openFundingTxIDs.contains(fundingOutpoint.txID) else { return }
        
        DispatchQueue.global(qos: .background).async {
            
            // Bind the wallet locally: resetNodeState can clear it while this
            // closure is parked on the background queue.
            guard let bdkWallet = self.bdkWallet else { return }
            
            for eachCanonicalTx in bdkWallet.transactions() {
                let spendsFundingOutput = eachCanonicalTx.transaction.input().contains { eachInput in
                    eachInput.previousOutput.txid == fundingOutpoint.txID && eachInput.previousOutput.vout == fundingOutpoint.vout
                }
                if spendsFundingOutput {
                    CacheManager.storeChannelClosureTxIDs(txIDs: [eachCanonicalTx.transaction.computeTxid()])
                    CacheManager.removeChannelFundingOutpoint()
                    return
                }
            }
        }
    }
    
    func getBittrAddress() -> String {
        let bittrAddress = self.bdkWallet!.peekAddress(keychain: .external, index: 0).address.description
        return bittrAddress
    }
    
    func revealAddresses(toIndex:Int) {
        guard let bdkWallet = self.bdkWallet else {
            Log.info("BDK wallet unavailable; not revealing addresses to index \(toIndex).")
            return
        }
        // Make sure peeked addresses are also revealed, so that they're updated in any lightSync.
        let newlyRevealedAddresses = bdkWallet.revealAddressesTo(keychain: .external, index: UInt32(toIndex))
        guard newlyRevealedAddresses.count > 0 else { return }
        guard let connection = self.connection else {
            Log.info("No BDK connection; \(newlyRevealedAddresses.count) revealed addresses were not persisted.")
            return
        }

        do {
            _ = try bdkWallet.persist(connection: connection)
        } catch {
            self.handleError(error: error, row: 468)
        }
    }
    
    func getAddress(atIndex:Int, doReveal:Bool = true) -> String? {
        if doReveal { self.revealAddresses(toIndex: atIndex) }
        guard let bdkWallet = self.bdkWallet else {
            Log.info("BDK wallet unavailable; could not derive address at index \(atIndex).")
            return nil
        }
        let thisAddress = bdkWallet.peekAddress(keychain: .external, index: UInt32(atIndex)).address.description
        return thisAddress
    }
}

extension Error {
    
    var isCorruptDatabase:Bool {
        // SQLite's own wording for a damaged file, or one that isn't a database at all.
        let message:String
        switch self as Error {
        case SqliteError.Sqlite(let rusqliteError): message = rusqliteError
        case LoadWithPersistError.Persist(let errorMessage): message = errorMessage
        default: return false
        }
        return message.contains("database disk image is malformed") || message.contains("file is not a database")
    }
}
