//
//  BitcoinManager.swift
//  bittr
//
//  Created by Tom Melters on 18/07/2023.
//

import Foundation
import LDKNode
import BitcoinDevKit
import Sentry
import CryptoKit

class BitcoinManager {
    
    public var ldkNode: Node?
    private var network: LDKNode.Network
    private let storageManager = LightningStorage()
    private var connection: Connection?
    private var electrumClient: ElectrumClient?
    private var bdkWallet: BitcoinDevKit.Wallet?
    private var xpub = ""
    private var coreVC:CoreViewController?
    
    class var shared: BitcoinManager {
        struct Singleton {
            static let instance = BitcoinManager(network: EnvironmentConfig.ldkNetwork)
        }
        return Singleton.instance
    }
    
    init(network: LDKNode.Network) {
        self.network = network
    }
    
    func startLDK(completion: @escaping (Bool) -> Void) {
        
        // Delete previous LDK Node log.
        do {
            try FileManager.deleteLDKNodeLogLatestFile()
        } catch {
            Log.info("Could not delete LDK Node log latest file.")
        }
        
        // Congifure LDK Node settings.
        let correctListeningAddresses = EnvironmentConfig.isDevelopment ? ["0.0.0.0:19735"] : ["0.0.0.0:9735"]
        
        let config = Config(
            storageDirPath: self.storageManager.getDocumentsDirectory(),
            network: self.network,
            listeningAddresses: correctListeningAddresses,
            announcementAddresses: nil,
            nodeAlias: nil,
            trustedPeers0conf: [EnvironmentConfig.lightningNodeId],
            probingLiquidityLimitMultiplier: UInt64(3),
            anchorChannelsConfig: AnchorChannelsConfig(
                trustedPeersNoReserve: [ PublicKey(EnvironmentConfig.lightningNodeId) ],
                perChannelReserveSats: UInt64(1000)),
            routeParameters: nil
        )
        
        // Set mnemonic string.
        let mnemonicString:String
        if let cachedMnemonic = CacheManager.getMnemonic() {
            mnemonicString = cachedMnemonic
        } else {
            // No cached mnemonic available.
            Log.info("Could not get mnemonic from cache.")
            DispatchQueue.main.async {
                SentrySDK.capture(message: "Could not get mnemonic from cache.") { scope in
                    scope.setExtra(value: "BitcoinManager row 71", key: "context")
                }
                completion(false)
            }
            return
        }
        
        // Set LDK background syncing.
        let backgroundSync = BackgroundSyncConfig(
            onchainWalletSyncIntervalSecs: 30,
            lightningWalletSyncIntervalSecs: 30,
            feeRateCacheUpdateIntervalSecs: 300
        )
        // Set Esplora sync config (to be used in non-mainnet environments)
        let esploraSyncConfig = EsploraSyncConfig(backgroundSyncConfig: .some(backgroundSync))
        // Set Electrum sync config (to be used in mainnnet)
        let electrumSyncConfig = ElectrumSyncConfig(backgroundSyncConfig: .some(backgroundSync))

        // Node builder.
        let nodeBuilder = Builder.fromConfig(config: config)
        nodeBuilder.setEntropyBip39Mnemonic(mnemonic: mnemonicString, passphrase: "")
        
        // Configure LSP2 liquidity source to allow channels to be used up to 100% capacity
        // rather than the default 10% limit imposed by LDK. This enables better channel utilization
        // for receiving payments, though we're not yet using the full LSP2 specification.
        nodeBuilder.setLiquiditySourceLsps2(
            nodeId: PublicKey(EnvironmentConfig.lightningNodeId),
            address: EnvironmentConfig.lightningNodeAddress,
            token: ""
        )
        
        // Set correct network.
        switch network {
        case .bitcoin:
            nodeBuilder.setGossipSourceRgs(rgsServerUrl: EnvironmentConfig.RGSServerURLs.bitcoin)
            nodeBuilder.setChainSourceElectrum(serverUrl: EnvironmentConfig.electrumURL, config: electrumSyncConfig)
        case .regtest:
            nodeBuilder.setChainSourceEsplora(serverUrl: EnvironmentConfig.EsploraURLs.regtest, config: esploraSyncConfig)
        case .signet:
            nodeBuilder.setChainSourceEsplora(serverUrl: EnvironmentConfig.EsploraURLs.signet, config: esploraSyncConfig)
        case .testnet:
            nodeBuilder.setGossipSourceRgs(rgsServerUrl: EnvironmentConfig.RGSServerURLs.testnet)
            nodeBuilder.setChainSourceEsplora(serverUrl: EnvironmentConfig.EsploraURLs.testnet, config: esploraSyncConfig)
        }
        
//        let logDirectory = storageManager.getDocumentsDirectory() + "/logs"
//        try? FileManager.default.createDirectory(
//                   atPath: logDirectory,
//                   withIntermediateDirectories: true
//               )
//        
//        let logPath = logDirectory + "/ruben.log"
//        
//        nodeBuilder.setFilesystemLogger(logFilePath: logPath, maxLogLevel: LDKNode.LogLevel.trace)

        
        let newLdkNode: Node
        
        // Build new node.
        do {
            newLdkNode = try nodeBuilder.build()
        } catch {
            Log.info("Could not build newLdkNode. \(error)")
            DispatchQueue.main.async {
                SentrySDK.capture(error: error) { scope in
                    scope.setExtra(value: "BitcoinManager row 130", key: "context")
                }
                completion(false)
            }
            return
        }
        
        // Start new node.
        do {
            try newLdkNode.start()
            self.ldkNode = newLdkNode
            DispatchQueue.main.async {
                completion(true)
            }
        } catch {
            Log.info("Could not start newLdkNode. \(error)")
            DispatchQueue.main.async {
                SentrySDK.capture(error: error) { scope in
                    scope.setExtra(value: "BitcoinManager row 147", key: "context")
                }
                completion(false)
            }
        }
    }
    
    func getMnemonic() -> String {
        if let cachedMnemonic = CacheManager.getMnemonic() {
            // Existing mnemonic.
            return cachedMnemonic
        } else {
            // New mnemonic.
            Log.info("Did not find mnemonic. Creating a new one.")
            let newMnemonic:String = LDKNode.generateEntropyMnemonic(wordCount: .words12).description
            CacheManager.storeMnemonic(newMnemonic)
            return newMnemonic
        }
    }
    
    func setCoreVC(_ thisCoreVC:CoreViewController) {
        self.coreVC = thisCoreVC
    }
    
    func startBDK() {
        
        DispatchQueue.global(qos: .background).async {
            
            // BDK launch.
            if self.bdkWallet == nil {
                Log.info("Will start blockchain and wallet.")
                
                // Attempt to create a mnemonic object from the provided mnemonic string.
                let mnemonic:BitcoinDevKit.Mnemonic
                do {
                    mnemonic = try BitcoinDevKit.Mnemonic.fromString(mnemonic: CacheManager.getMnemonic()!)
                } catch {
                    self.handleError(error: error, row: 178, stopLightning: true)
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
                    self.handleError(error: error, row: 211, stopLightning: true)
                    return
                }
                
                do {
                    self.bdkWallet = try Wallet(descriptor: bip84ExternalDescriptor, changeDescriptor: bip84InternalDescriptor, network: EnvironmentConfig.bitcoinDevKitNetwork, connection: self.connection!)
                } catch {
                    self.handleError(error: error, row: 218, stopLightning: true)
                    return
                }
                
                // Configure and create an Electrum blockchain connection to interact with the Bitcoin network
                let electrum:BitcoinDevKit.ElectrumClient
                do {
                    electrum = try ElectrumClient(url: EnvironmentConfig.electrumURL)
                } catch {
                    self.handleError(error: error, row: 228, stopLightning: true)
                    return
                }
                self.electrumClient = electrum
                
                Log.info("Did initiate wallet and blockchain.")
                DispatchQueue.main.async {
                    SentrySDK.metrics.increment(key: "sync.bdk.success")
                    self.coreVC?.updateSync(action: .complete, type: .bdk)
                    self.coreVC?.updateSync(action: .start, type: .sync)
                }
            }
            
            // Proceed to wallet sync.
            self.initialWalletSync()
        }
    }
    
    
    func initialWalletSync() {
        Log.info("Will sync wallet.")
        // Synchronize the wallet with the blockchain, ensuring transaction data is up to date.
        
        // Check Electrum Client.
        if self.electrumClient == nil {
            do {
                self.electrumClient = try ElectrumClient(url: EnvironmentConfig.electrumURL)
            } catch {
                self.handleError(error: error, row: 222, stopLightning: true)
                return
            }
        }
        
        // Perform a full scan or a sync with BDK.
        var update:Update?
        /*if CacheManager.lastFullSync() != nil {
            Log.info("Will perform a light sync.")
            
            // Build request.
            var syncRequest:SyncRequest?
            do {
                syncRequest = try self.bdkWallet!.startSyncWithRevealedSpks().build()
            } catch {
                self.handleError(error: error, row: 283, stopLightning: true)
                return
            }
            
            // Run light sync.
            do {
                update = try self.electrumClient!.sync(
                    request: syncRequest!,
                    batchSize: UInt64(25),
                    fetchPrevTxouts: true
                )
            } catch {
                self.handleError(error: error, row: 281, stopLightning: true)
                return
            }
        } else {*/
            Log.info("Will perform a full scan.")
            
            // Build request.
            var syncRequest:FullScanRequest?
            do {
                syncRequest = try self.bdkWallet!.startFullScan().build()
            } catch {
                self.handleError(error: error, row: 212, stopLightning: true)
                return
            }
            
            // Run full scan.
            do {
                update = try self.electrumClient!.fullScan(
                    request: syncRequest!,
                    stopGap: UInt64(25),
                    batchSize: UInt64(25),
                    fetchPrevTxouts: true
                )
            } catch {
                self.handleError(error: error, row: 236, stopLightning: true)
                return
            }
            
            // Update cache.
            //CacheManager.newFullSync()
        //}
        
        // Apply update to BDK wallet.
        do {
            try self.bdkWallet!.applyUpdate(update: update!)
        } catch {
            self.handleError(error: error, row: 243, stopLightning: true)
            return
        }
        
        // Persist wallet changes.
        do {
            let _ = try self.bdkWallet!.persist(connection: self.connection!)
        } catch {
            self.handleError(error: error, row: 250, stopLightning: false)
        }
        
        // Update syncing status.
        Log.info("Did sync wallet.")
        DispatchQueue.main.async {
            SentrySDK.metrics.increment(key: "sync.walletsync.success")
            self.coreVC?.updateSync(action: .complete, type: .sync)
            self.coreVC?.updateSync(action: .start, type: .final)
        }
        
        Task {
            // Get latest block height.
            let _ = await self.didGetLatestBlockHeight()
            
            // Check peer connection.
            let peerIsConnected = await self.coreVC!.isConnectedToPeer()
            DispatchQueue.global(qos: .background).async {
                if peerIsConnected {
                    // We're already connected to peer.
                    self.getChannelsAndPayments()
                } else {
                    // Connect to peer.
                    self.connectToLightningPeer()
                }
            }
        }
    }
    
    func didGetLatestBlockHeight() async -> Bool {
        
        var receivedDictionary:NSDictionary
        do {
            receivedDictionary = try await withCheckedThrowingContinuation { continuation in
                Task {
                    await CallsManager.makeApiCall(url: "https://mempool.space/api/blocks/tip/height", parameters: nil, getOrPost: .get) { result in
                        switch result {
                        case .success(let receivedDictionary):
                            continuation.resume(returning: receivedDictionary)
                        case .failure(let error):
                            continuation.resume(throwing: error)
                        }
                    }
                }
            }
        } catch {
            DispatchQueue.main.async {
                SentrySDK.capture(error: error) { scope in
                    scope.setExtra(value: "BitcoinManager row 385", key: "context")
                }
            }
            return false
        }
        
        if let blockHeight = receivedDictionary["result"] as? Int {
            Log.info("Block height: \(blockHeight)")
            self.coreVC?.bittrWallet.currentHeight = blockHeight
            return true
        } else {
            DispatchQueue.main.async {
                SentrySDK.capture(message: "Could not get latest block height. \(receivedDictionary)") { scope in
                    scope.setExtra(value: "BitcoinManager row 377", key: "context")
                }
            }
            return false
        }
    }
    
    func handleError(error:Error, row:Int, stopLightning:Bool) {
        Log.info("Some error occurred. \(error.localizedDescription)")
        let errorMessage:String = {
            if let esploraError = error as? BitcoinDevKit.EsploraError {
                return esploraError.getErrorMessage()
            } else if let electrumError = error as? BitcoinDevKit.ElectrumError {
                return electrumError.getErrorMessage()
            } else if let cannotConnectError = error as? BitcoinDevKit.CannotConnectError {
                return cannotConnectError.getErrorMessage()
            } else {
                return error.localizedDescription
            }
        }()
        if stopLightning {
            self.coreVC?.stopLightning(message: errorMessage)
        }
        DispatchQueue.main.async {
            SentrySDK.capture(error: error) { scope in
                scope.setExtra(value: "BitcoinManager row \(row)", key: "context")
            }
            SentrySDK.metrics.increment(key: "sync.walletsync.failure")
        }
    }
    
    
    func connectToLightningPeer() {
        
        Task {
            let didEstablishPeerConnection = await self.didEstablishPeerConnection()
            
            DispatchQueue.main.async {
                self.getChannelsAndPayments()
            }
            
            if !didEstablishPeerConnection {
                do {
                    let nodeId = EnvironmentConfig.lightningNodeId
                    try BitcoinManager.shared.ldkNode?.disconnect(nodeId: nodeId)
                } catch {
                    let errorMessage:String = {
                        if let nodeError = error as? NodeError {
                            return handleNodeError(nodeError).title + ", " + handleNodeError(nodeError).detail
                        } else {
                            return "No error message"
                        }
                    }()
                    DispatchQueue.main.async {
                        Log.info("Can't disconnect from peer: \(errorMessage).")
                        SentrySDK.capture(error: error) { scope in
                            scope.setExtra(value: "BitcoinManager row 277", key: "context")
                        }
                    }
                }
            }
        }
    }
    
    
    func didEstablishPeerConnection() async -> Bool {
        
        return await withTaskGroup(of: Bool.self) { group -> Bool in
            
            // Peer connection task.
            group.addTask {
                do {
                    try await BitcoinManager.shared.connect(
                        nodeId: EnvironmentConfig.lightningNodeId,
                        address: EnvironmentConfig.lightningNodeAddress,
                        persist: true
                    )
                    Log.info("Did connect to peer.")
                    return true
                } catch {
                    let errorMessage:String = {
                        if let nodeError = error as? NodeError {
                            return handleNodeError(nodeError).title + ", " + handleNodeError(nodeError).detail
                        } else {
                            return "No error message"
                        }
                    }()
                    DispatchQueue.main.async {
                        // Handle UI error showing here, like showing an alert
                        Log.info("Can't connect to peer: \(errorMessage).")
                        SentrySDK.capture(error: error) { scope in
                            scope.setExtra(value: "BitcoinManager row 319", key: "context")
                        }
                    }
                    return false
                }
            }
            
            // 5 second timer.
            group.addTask {
                do {
                    try await Task.sleep(nanoseconds: UInt64(5) * NSEC_PER_SEC)
                } catch {
                    return false
                }
                Log.info("Connecting to peer takes too long.")
                return false
            }
            
            // Result of whichever task succeeds first.
            let first = await group.next() ?? false
            group.cancelAll()
            return first
        }
    }
    
    
    func getChannelsAndPayments() {
        
        // Get channels.
        let channels = BitcoinManager.shared.listChannels()
        
        // Get funding transaction ID.
        if let activeChannel = channels.getActiveChannel() {
            if let channelTxoID = activeChannel.fundingTxo?.txid as? String {
                CacheManager.storeTxoID(txoID: channelTxoID)
            }
        }
        
        // Get transactions.
        let payments = BitcoinManager.shared.listPayments()
        
        // Handle details in HomeVC.
        DispatchQueue.main.async {
            self.coreVC?.bittrWallet.lightningChannels = channels
            self.coreVC?.bittrWallet.allTransactions = payments
            self.coreVC?.homeVC?.loadWalletData()
        }
    }
    
    func stop() throws {
        if let actualLdkNode = ldkNode {
            try actualLdkNode.stop()
        }
    }
    
    func nodeId() -> String? {
        if self.ldkNode != nil {
            let nodeID = self.ldkNode!.nodeId()
            return nodeID
        } else {
            return nil
        }
    }
    
    func signMessage(message: String) async throws -> String {
        guard let data = message.data(using: .utf8) else {
            throw NSError(domain: "InvalidInput", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid input string. Couldn't convert to UTF8 data."])
        }
        
        let bytes = [UInt8](data)
        let signedMessage = self.ldkNode!.signMessage(msg: bytes)
        
        return signedMessage
    }
    
    func listPeers() -> [PeerDetails] {
        guard self.ldkNode != nil else {
            return []
        }
        let peers = self.ldkNode!.listPeers()
        return peers
    }
    
    func listPayments() -> [PaymentDetails] {
        guard self.ldkNode != nil else {
            return []
        }
        let payments = self.ldkNode!.listPayments()
        return payments
    }
    
    func listChannels() -> [LDKNode.ChannelDetails] {
        guard self.ldkNode != nil else {
            return []
        }
        let channels = self.ldkNode!.listChannels()
        return channels
    }
    
    func connect(nodeId: PublicKey, address: String, persist: Bool) async throws {
        try self.ldkNode!.connect(
            nodeId: nodeId,
            address: address,
            persist: persist
        )
    }
    
    func status() -> NodeStatus? {
        let status = self.ldkNode?.status()
        return status
    }
    
    func lightSync(completion: @escaping (Bool) -> Void) {
        
        guard (self.bdkWallet != nil &&
               self.electrumClient != nil &&
               self.coreVC != nil &&
               self.getEsploraClient() != nil) else {
            completion(false)
            return
        }
        
        DispatchQueue.global(qos: .background).async {
            Log.info("Will light sync wallet.")
            
            // Create sync request.
            let syncRequest:SyncRequest
            do {
                syncRequest = try self.bdkWallet!.startSyncWithRevealedSpks().build()
            } catch {
                self.handleError(error: error, row: 570, stopLightning: false)
                completion(false)
                return
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
                completion(false)
                return
            }
            
            // Apply update to wallet.
            do {
                try self.bdkWallet!.applyUpdate(update: update)
            } catch {
                self.handleError(error: error, row: 594, stopLightning: false)
            }
            
            // Persist update to wallet.
            do {
                let _ = try self.bdkWallet!.persist(connection: self.connection!)
            } catch {
                self.handleError(error: error, row: 603, stopLightning: false)
            }
            
            // Sync LDKNode.
            do {
                _ = try self.syncWallets()
            } catch {
                self.handleError(error: error, row: 660, stopLightning: false)
            }
            
            // Check if any changes have been found.
            if self.coreVC!.bittrWallet.satoshisOnchain != Int(self.ldkNode!.listBalances().totalOnchainBalanceSats) || self.coreVC!.bittrWallet.allTransactions.count != self.listPayments().count {
                
                // Update balance.
                self.coreVC!.bittrWallet.satoshisOnchain = Int(self.ldkNode!.listBalances().totalOnchainBalanceSats)
                
                // Update transactions.
                self.coreVC!.bittrWallet.allTransactions = self.listPayments()
                
                // Update channels.
                self.coreVC!.bittrWallet.lightningChannels = BitcoinManager.shared.listChannels()
                
                Task {
                    // Get latest block height.
                    let _ = await self.didGetLatestBlockHeight()
                    
                    DispatchQueue.main.async {
                        self.coreVC!.homeVC!.loadWalletData()
                        self.coreVC!.homeVC!.moveVC?.updateLabels()
                        completion(true)
                    }
                }
            } else {
                DispatchQueue.main.async { completion(false) }
            }
        }
    }
    
    func getFeeEstimates() async -> NSDictionary? {
        
        var receivedDictionary:NSDictionary
        do {
            receivedDictionary = try await withCheckedThrowingContinuation { continuation in
                Task {
                    await CallsManager.makeApiCall(url: "https://mempool.space/api/v1/fees/precise", parameters: nil, getOrPost: .get) { result in
                        switch result {
                        case .success(let receivedDictionary):
                            let mutableDictionary = receivedDictionary.mutableCopy() as! NSMutableDictionary
                            for (key, value) in mutableDictionary {
                                if (value as? Double) == nil || (key as? String) == nil { continuation.resume(returning: receivedDictionary) }
                                if (value as! Double) < 1 {
                                    // Minimum fee is 1 sat/vByte.
                                    mutableDictionary.setValue(Double(1), forKey: (key as! String))
                                } else {
                                    // LDKNode requires a rounded number for sat/vByte.
                                    mutableDictionary.setValue((value as! Double).rounded(), forKey: (key as! String))
                                }
                            }
                            continuation.resume(returning: mutableDictionary)
                        case .failure(let error):
                            continuation.resume(throwing: error)
                        }
                    }
                }
            }
        } catch {
            DispatchQueue.main.async {
                SentrySDK.capture(error: error) { scope in
                    scope.setExtra(value: "BitcoinManager row 385", key: "context")
                }
            }
            return nil
        }
        
        return receivedDictionary
    }
    
    func syncWallets() throws {
        try self.ldkNode!.syncWallets()
    }
    
    func getXpub() -> String {
        return self.xpub
    }
    
    func walletReset() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            // Remove last full sync from cache.
            UserDefaults.standard.removeObject(forKey: "lastFullSync")
            // Restart BDK.
            self.startBDK()
        }
    }
    
    func receivePayment(amountMsat: UInt64, description: String, expirySecs: UInt32) async throws -> Bolt11Invoice {
        let invoiceDescription = Bolt11InvoiceDescription.direct(description: description)
        let invoice = try self.ldkNode!.bolt11Payment().receive(amountMsat: amountMsat, description: invoiceDescription, expirySecs: expirySecs)
        return invoice
    }
    
    func receivePaymentWithHash(amountMsat: UInt64, descriptionHash: String, expirySecs: UInt32) async throws -> Bolt11Invoice {
        let invoiceDescription = Bolt11InvoiceDescription.hash(hash: descriptionHash)
        let invoice = try self.ldkNode!.bolt11Payment().receive(amountMsat: amountMsat, description: invoiceDescription, expirySecs: expirySecs)
        return invoice
    }
    
    func sendPayment(invoice: Bolt11Invoice) async throws -> PaymentHash {
        let paymentHash = try self.ldkNode!.bolt11Payment().send(invoice: invoice, routeParameters: nil)
        return paymentHash
    }
    
    func sendZeroAmountPayment(invoice: Bolt11Invoice, amount:Int) async throws -> PaymentHash {
        let paymentHash = try self.ldkNode!.bolt11Payment().sendUsingAmount(invoice: invoice, amountMsat: UInt64(amount*1000), routeParameters: nil)
        return paymentHash
    }
    
    func getNewOnchainAddress() -> String? {
        
        if self.ldkNode == nil {
            return nil
        } else {
            do {
                let newAddress = try self.ldkNode!.onchainPayment().newAddress()
                return newAddress.description
            } catch {
                return nil
            }
        }
    }
    
    func sendOnchainPayment(address:String, amountSats:UInt64, feeRateSatVb:UInt64) throws -> String {
        
        // Set fee rate.
        let feeRate = LDKNode.FeeRate.fromSatPerVbUnchecked(satVb: feeRateSatVb)
        
        // Broadcast transaction.
        let onchainID = try self.ldkNode!.onchainPayment().sendToAddress(address: address, amountSats: amountSats, feeRate: feeRate)
        
        // Return transaction ID.
        return onchainID.description
    }
    
    func getPaymentDetails(paymentHash: PaymentHash) -> PaymentDetails? {
        if let invoiceDetails = self.ldkNode!.payment(paymentId: paymentHash) {
            return invoiceDetails
        } else {
            return nil
        }
    }
    
    func getClient() -> ElectrumClient? {
        return self.electrumClient
    }
    
    func getEsploraClient() -> EsploraClient? {
        return EsploraClient(url: EnvironmentConfig.esploraURL)
    }
    
    func deleteDocuments() throws {
        try FileManager.default.deleteAllContentsInDocumentsDirectory()
    }
    
    func resetNodeState() {
        Log.info("🔍 [DEBUG] BitcoinManager - Resetting node state")
        
        // Clear node reference
        self.ldkNode = nil
        
        // Clear wallet reference
        self.bdkWallet = nil
        
        // Clear connection reference
        self.connection = nil
        
        // Clear electrum client reference
        self.electrumClient = nil
        
        // Reset other state variables
        self.xpub = ""
        
        Log.info("🔍 [DEBUG] BitcoinManager - Node state reset completed")
    }
    
    func listenForEvents() {
        
        DispatchQueue.global(qos: .background).async {
            let event = self.ldkNode!.waitNextEvent()
            self.coreVC?.ldkEventReceived(event: event)
            
            do {
                try self.ldkNode!.eventHandled()
            } catch {
                Log.info("Error: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    SentrySDK.capture(error: error) { scope in
                        scope.setExtra(value: "BitcoinManager row 564", key: "context")
                    }
                }
            }
            self.listenForEvents()
        }
    }
    
    func closeChannel(userChannelId: ChannelId, counterPartyNodeId:PublicKey) throws {
        try self.ldkNode!.closeChannel(
            userChannelId: userChannelId,
            counterpartyNodeId: counterPartyNodeId
        )
    }

    func connectOpenChannel(
        nodeId: PublicKey,
        address: String,
        channelAmountSats: UInt64,
        pushToCounterpartyMsat: UInt64?,
        channelConfig: ChannelConfig?,
        announceChannel: Bool = false
    ) async throws -> UserChannelId {
        let userChannelId = try self.ldkNode!.openChannel(
            nodeId: nodeId,
            address: address,
            channelAmountSats: channelAmountSats,
            pushToCounterpartyMsat: pushToCounterpartyMsat,
            channelConfig: nil
        )
        return userChannelId
    }

    func forceCloseChannel(userChannelId: ChannelId, counterPartyNodeId:PublicKey) throws {
        // TODO: This currently doesn't work properly because the bittr node is in the trusted_peers_no_reserve
        try self.ldkNode!.forceCloseChannel(userChannelId: userChannelId,
                                            counterpartyNodeId: counterPartyNodeId, reason: "" )
    }
    
    func getPrivatePublicKeyForPath(path: String) throws -> (privateKeyHex: String, publicKeyHex: String) {
        // Determine network based on environment
        let network: KeyDerivationNetwork = EnvironmentConfig.isDevelopment ? .testnet : .mainnet
        
        // Create SimpleKeyDerivation instance with the stored mnemonic
        let keyDerivation = try SimpleKeyDerivation(mnemonic: CacheManager.getMnemonic()!, network: network)
            
        // Derive keys for the given path
        let (privateKeyHex, publicKeyHex) = try keyDerivation.getPrivatePublicKeyForPath(path)

        return (privateKeyHex, publicKeyHex)
    }

        
    func signMessageForPath(path: String, message: String) throws -> String {
        // Get private keys in hex format (to be used in the message signing function)
        let (privateKey, _) = try getPrivatePublicKeyForPath(path: path)

        return try BitcoinMessage.sign(message: message, privateKeyHex: privateKey, segwitType: .p2wpkh)
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
            tx = try BitcoinManager.shared.getTx(address: address, amountSats: amountSats, selectedVbyte: selectedVbyte)
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

enum WalletError: Error {
    case walletNotInitiated
    case clientNotInitiated
}

extension FileManager {
    
    func deleteAllContentsInDocumentsDirectory() throws {
        
        if #available(iOS 16.0, *) {
            let documentsURL = URL.documentsDirectory
            let contents = try contentsOfDirectory(at: documentsURL, includingPropertiesForKeys: nil, options: [])
            for fileURL in contents {
                try removeItem(at: fileURL)
            }
        } else {
            // Fallback on earlier versions
            try FileManager.default.removeItem(atPath: LightningStorage().getDocumentsDirectory())
        }
    }
}

extension Connection {
    
    static func createConnection() throws -> Connection {
        let documentsDirectoryURL = URL.documentsDirectory
        let walletDataDirectoryURL = documentsDirectoryURL.appendingPathComponent("wallet_data")

        if FileManager.default.fileExists(atPath: walletDataDirectoryURL.path) {
            try FileManager.default.removeItem(at: walletDataDirectoryURL)
        }

        try FileManager.default.ensureDirectoryExists(at: walletDataDirectoryURL)
        try FileManager.default.removeOldFlatFileIfNeeded(at: documentsDirectoryURL)
        let persistenceBackendPath = walletDataDirectoryURL.appendingPathComponent("wallet.sqlite")
            .path
        let connection = try Connection(path: persistenceBackendPath)
        return connection
    }
}

extension FileManager {

    func ensureDirectoryExists(at url: URL) throws {
        var isDir: ObjCBool = false
        if fileExists(atPath: url.path, isDirectory: &isDir) {
            if !isDir.boolValue {
                try removeItem(at: url)
            }
        }
        if !fileExists(atPath: url.path) {
            try createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
        }
    }

    func removeOldFlatFileIfNeeded(at directoryURL: URL) throws {
        let flatFileURL = directoryURL.appendingPathComponent("wallet_data")
        var isDir: ObjCBool = false
        if fileExists(atPath: flatFileURL.path, isDirectory: &isDir) {
            if !isDir.boolValue {
                try removeItem(at: flatFileURL)
            }
        }
    }
}

extension String {    
    func sha256() -> String {
        let data = self.data(using: .utf8)!
        let hash = SHA256.hash(data: data)
        return hash.map { String(format: "%02x", $0) }.joined()
    }
}
