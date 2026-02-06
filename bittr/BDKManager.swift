//
//  BDKManager.swift
//  bittr
//
//  Created by Tom Melters on 2/6/26.
//

import Foundation
import BitcoinDevKit
import Sentry

extension BitcoinManager {
    
    func didStartBDK(completion: @escaping (Bool) -> Void) {
        DispatchQueue.global(qos: .background).async {
            
            // BDK launch.
            if self.bdkWallet == nil {
                Log.info("Will start blockchain and wallet.")
                
                // Attempt to create a mnemonic object from the provided mnemonic string.
                let mnemonic:BitcoinDevKit.Mnemonic
                do {
                    mnemonic = try BitcoinDevKit.Mnemonic.fromString(mnemonic: CacheManager.getMnemonic()!)
                } catch {
                    self.handleError(error: error, row: 178, stopLightning: false)
                    completion(false)
                    return
                }
                
                // Create a BIP32 extended root key using the mnemonic and a nil password
                let bip32ExtendedRootKey = DescriptorSecretKey(network: EnvironmentConfig.isDevelopment ? .signet : .bitcoin, mnemonic: mnemonic, password: nil)
                
                // Create a BIP84 external descriptor using the BIP32 extended root key, specifying the keychain as external and the network as testnet
                let bip84ExternalDescriptor = Descriptor.newBip84(secretKey: bip32ExtendedRootKey, keychain: .external, network: EnvironmentConfig.isDevelopment ? .signet : .bitcoin)
                
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
                    self.handleError(error: error, row: 211, stopLightning: false)
                    completion(false)
                    return
                }
                
                do {
                    self.bdkWallet = try Wallet(descriptor: bip84ExternalDescriptor, changeDescriptor: bip84InternalDescriptor, network: EnvironmentConfig.bitcoinDevKitNetwork, connection: self.connection!)
                } catch {
                    self.handleError(error: error, row: 218, stopLightning: false)
                    completion(false)
                    return
                }
                
                // Configure and create an Electrum blockchain connection to interact with the Bitcoin network
                do {
                    self.electrumClient = try ElectrumClient(url: EnvironmentConfig.electrumURL)
                } catch {
                    self.handleError(error: error, row: 228, stopLightning: false)
                    completion(false)
                    return
                }
                
                Log.info("Did initiate wallet and blockchain.")
                DispatchQueue.main.async {
                    SentrySDK.metrics.count(key: "sync.bdk.success")
                    self.coreVC?.updateSync(action: .complete, type: .bdk)
                    self.coreVC?.updateSync(action: .start, type: .sync)
                    completion(true)
                }
            }
        }
    }
    
    func didSyncBdkWallet(completion: @escaping (Bool) -> Void) {
        Log.info("Will sync BDK wallet.")
        // Synchronize the wallet with the blockchain, ensuring transaction data is up to date.
        
        DispatchQueue.global(qos: .background).async {
            // Check Electrum Client.
            if self.electrumClient == nil {
                do {
                    self.electrumClient = try ElectrumClient(url: EnvironmentConfig.electrumURL)
                } catch {
                    self.handleError(error: error, row: 222, stopLightning: false)
                    completion(false)
                    return
                }
            }
            
            // Perform a full scan.
            Log.info("Will perform a full scan.")
            
            // Build request.
            let syncRequest:FullScanRequest
            do {
                syncRequest = try self.bdkWallet!.startFullScan().build()
            } catch {
                self.handleError(error: error, row: 212, stopLightning: false)
                completion(false)
                return
            }
            
            // Run full scan.
            let update:Update
            do {
                update = try self.electrumClient!.fullScan(
                    request: syncRequest,
                    stopGap: UInt64(25),
                    batchSize: UInt64(25),
                    fetchPrevTxouts: true
                )
            } catch {
                self.handleError(error: error, row: 236, stopLightning: false)
                completion(false)
                return
            }
            
            // Apply update to BDK wallet.
            do {
                try self.bdkWallet!.applyUpdate(update: update)
            } catch {
                self.handleError(error: error, row: 243, stopLightning: false)
                completion(false)
                return
            }
            
            // Persist wallet changes.
            do {
                let _ = try self.bdkWallet!.persist(connection: self.connection!)
            } catch {
                self.handleError(error: error, row: 250, stopLightning: false)
            }
            
            // Update syncing status.
            Log.info("Did sync BDK wallet.")
            completion(true)
        }
    }
    
    func lightSyncBdkWallet() -> Bool {
        
        // Create sync request.
        let syncRequest:SyncRequest
        do {
            syncRequest = try self.bdkWallet!.startSyncWithRevealedSpks().build()
        } catch {
            self.handleError(error: error, row: 570, stopLightning: false)
            return false
        }
        
        // Create update.
        let update:Update
        do {
            update = try self.electrumClient!.sync(
                request: syncRequest,
                batchSize: UInt64(25),
                fetchPrevTxouts: true
            )
        } catch {
            self.handleError(error: error, row: 582, stopLightning: false)
            return false
        }
        
        // Apply update to wallet.
        do {
            try self.bdkWallet!.applyUpdate(update: update)
        } catch {
            self.handleError(error: error, row: 594, stopLightning: false)
        }
        
        // Persist update to wallet.
        do {
            _ = try self.bdkWallet!.persist(connection: self.connection!)
        } catch {
            self.handleError(error: error, row: 603, stopLightning: false)
        }
        
        return true
    }
    
    func getSize(address:String, amountSats:Int) throws -> UInt64 {
        
        let tx = try self.getTx(address: address, amountSats: amountSats, selectedVbyte: nil)
        let size = tx.vsize()
        
        return size
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
        if selectedVbyte != nil {
            txBuilder = txBuilder.feeRate(feeRate: try FeeRate.fromSatPerVb(satVb: UInt64(selectedVbyte!)))
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
}
