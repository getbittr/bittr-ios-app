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

extension BitcoinManager {
    
    func didStartBDK() -> Bool {
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
        
        // Initialize a wallet instance using the BIP84 external and internal descriptors, testnet network, and SQLite database configuration
        do {
            self.connection = try Connection.createConnection()
        } catch {
            self.handleError(error: error, row: 211)
            return false
        }
        
        do {
            self.bdkWallet = try Wallet(descriptor: bip84ExternalDescriptor, changeDescriptor: bip84InternalDescriptor, network: EnvironmentConfig.bitcoinDevKitNetwork, connection: self.connection!)
        } catch {
            self.handleError(error: error, row: 218)
            return false
        }
        
        // Configure and create an Electrum blockchain connection to interact with the Bitcoin network
        do {
            self.electrumClient = try ElectrumClient(url: EnvironmentConfig.electrumURL)
        } catch {
            self.handleError(error: error, row: 228)
            return false
        }
        
        Log.info("Did initiate wallet and blockchain.")
        SentryManager.countMetric("sync.bdk.success")
        return true
    }
    
    func didSyncBdkWallet(completion originalCompletion: @escaping (Bool) -> Void) {
        Log.info("Will sync BDK wallet.")
        self.bdkWalletIsScanning = true
        self.bdkFullScanTimedOut = false

        // The watchdog below hands the caller a failure, but it cannot stop the
        // scan — so `bdkWalletIsScanning` stays set and every scan-gated screen
        // stays blocked until the app is restarted. Callers surface that via
        // `bdkFullScanTimedOut` rather than the generic "try again later" copy,
        // which would be a lie: nothing the user does in this session will help.
        //
        // NOTE: `timeout` must stay comfortably above a legitimately slow scan
        // (the fullScan below is documented as "seconds to minutes"), or slow
        // syncs get reported as failures. Tune before shipping.
        let timeout: TimeInterval = 180
        var didComplete = false
        func completion(_ success: Bool) {
            DispatchQueue.main.async {
                guard !didComplete else { return }
                didComplete = true
                originalCompletion(success)
            }
        }
        DispatchQueue.global(qos: .background).asyncAfter(deadline: .now() + timeout) {
            Log.info("BDK full scan timed out after \(Int(timeout))s; failing so callers don't hang.")
            self.bdkFullScanTimedOut = true
            completion(false)
        }

        // Synchronize the wallet with the blockchain, ensuring transaction data is up to date.
        
        DispatchQueue.global(qos: .background).async {
            // Check Electrum Client.
            if self.electrumClient == nil {
                do {
                    self.electrumClient = try ElectrumClient(url: EnvironmentConfig.electrumURL)
                } catch {
                    self.handleError(error: error, row: 222)
                    self.bdkWalletIsScanning = false
                    completion(false)
                    return
                }
            }

            // Bind references locally so the rest of the closure works on
            // a consistent snapshot. resetNodeState (from performWalletReset)
            // can clear bdkWallet / electrumClient / connection while this
            // closure is parked on the background queue mid-fullScan; the
            // earlier `self.bdkWallet!` force-unwraps would then trap with
            // a Swift _assertionFailure when the closure resumed.
            guard let bdkWallet = self.bdkWallet,
                  let electrumClient = self.electrumClient,
                  let connection = self.connection else {
                self.bdkWalletIsScanning = false
                completion(false)
                return
            }

            // Perform a full scan.
            Log.info("Will perform a full scan.")

            // Build request.
            let syncRequest:FullScanRequest
            do {
                syncRequest = try bdkWallet.startFullScan().build()
            } catch {
                self.handleError(error: error, row: 212)
                self.bdkWalletIsScanning = false
                completion(false)
                return
            }

            // Run full scan. This is the long pole — seconds to minutes —
            // and the most likely window for resetNodeState to run.
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
                self.bdkWalletIsScanning = false
                completion(false)
                return
            }

            // If resetNodeState ran during fullScan above, our local
            // bdkWallet now points at a torn-down wallet whose on-disk
            // SQLite files were removed by deleteDocuments. Applying and
            // persisting the update against it would either fail or
            // corrupt the next install's state — bail cleanly instead.
            guard self.bdkWallet === bdkWallet else {
                self.bdkWalletIsScanning = false
                completion(false)
                return
            }

            // Apply update to BDK wallet.
            do {
                try bdkWallet.applyUpdate(update: update)
            } catch {
                self.handleError(error: error, row: 243)
                self.bdkWalletIsScanning = false
                completion(false)
                return
            }

            // Persist wallet changes.
            do {
                let _ = try bdkWallet.persist(connection: connection)
            } catch {
                self.handleError(error: error, row: 250)
            }

            // Update syncing status.
            Log.info("Did sync BDK wallet.")
            self.bdkWalletIsScanning = false
            self.bdkWalletHasBeenScanned = true
            completion(true)
        }
    }
    
    func lightSyncBdkWallet() -> Bool {
        // Stand down while a full scan is running. Both work through the same
        // wallet, electrum client and SQLite connection, which serialize
        // internally — so overlapping them doesn't corrupt anything, it starves
        // the scan behind a light sync that re-fires every 30s until the scan's
        // watchdog gives up. BackgroundSync has no idea a scan is in flight, so
        // the check has to live here.
        guard !self.bdkWalletIsScanning else {
            Log.info("Skipping light sync — a BDK full scan is in progress.")
            return false
        }

        guard let bdkWallet = self.bdkWallet,
              let electrumClient = self.electrumClient,
              let connection = self.connection else {
            return false
        }
        
        // Create sync request.
        let syncRequest:SyncRequest
        do {
            syncRequest = try bdkWallet.startSyncWithRevealedSpks().build()
        } catch {
            self.handleError(error: error, row: 570)
            return false
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
            return false
        }
        
        // Ensure bdkWallet hasn't been cleared in the meantime.
        guard self.bdkWallet === bdkWallet else {
            return false
        }
        
        // Apply update to wallet.
        do {
            try bdkWallet.applyUpdate(update: update)
        } catch {
            self.handleError(error: error, row: 594)
            return false
        }
        
        // Persist update to wallet.
        do {
            _ = try bdkWallet.persist(connection: connection)
        } catch {
            self.handleError(error: error, row: 603)
        }
        
        return true
    }
    
    func getSize(address:String, amountSats:Int, selectedVbyte:Float?) throws -> UInt64 {
        
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
    
    func getTx(address:String, amountSats:Int, selectedVbyte:Float?) throws -> BitcoinDevKit.Transaction {
        
        let details = try self.getPsbt(address: address, amountSats: amountSats, selectedVbyte: selectedVbyte)
        let tx = try details.extractTx()
        
        return tx
    }
    
    func getPsbt(address:String, amountSats:Int, selectedVbyte:Float?) throws -> BitcoinDevKit.Psbt {
        
        guard self.bdkWallet != nil else {
            throw WalletError.walletNotInitiated
        }
        
        let network = EnvironmentConfig.bitcoinDevKitNetwork
        let address = try Address(address: address, network: network)
        let script = address.scriptPubkey()
        var txBuilder = TxBuilder().addRecipient(script: script, amount: BitcoinDevKit.Amount.fromSat(satoshi: UInt64(amountSats)))
        if let selectedVbyte = selectedVbyte {
            // Minimum 1 sat/Vbyte.
            txBuilder = txBuilder.feeRate(feeRate: try FeeRate.fromSatPerVb(satVb: max(UInt64(selectedVbyte), 1)))
        }
        let details = try txBuilder.finish(wallet: self.bdkWallet!)
        let _ = try self.bdkWallet!.sign(psbt: details, signOptions: nil)
        
        return details
    }
    
    func sendOnchainTransaction(address:String, amountSats:Int, selectedVbyte:Float?) throws -> [String] {
        
        // Create transaction.
        let tx:BitcoinDevKit.Transaction
        do {
            tx = try self.getTx(address: address, amountSats: amountSats, selectedVbyte: selectedVbyte)
        } catch {
            throw error
        }
        
        // Check Electrum availability.
        guard self.electrumClient != nil else {
            throw WalletError.clientNotInitiated
        }
        
        // Broadcast transaction.
        let txId:String
        do {
            txId = try self.electrumClient!.transactionBroadcast(tx: tx)
        } catch {
            throw error
        }
        
        let rawData = tx.serialize().map { String(format: "%02hhx", $0) }.joined()
        return [txId, rawData]
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
    
    func getBittrAddress() -> String {
        let bittrAddress = self.bdkWallet!.peekAddress(keychain: .external, index: 0).address.description
        return bittrAddress
    }
    
    func getAddress(atIndex:Int) -> String {
        let thisAddress = self.bdkWallet!.peekAddress(keychain: .external, index: UInt32(atIndex)).address.description
        return thisAddress
    }
}
