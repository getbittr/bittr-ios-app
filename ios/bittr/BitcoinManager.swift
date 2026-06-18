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
    
    // LDK Node
    public var ldkNode: LDKNode.Node?
    private var network: LDKNode.Network
    
    // BDK
    var bdkWallet: BitcoinDevKit.Wallet?
    var electrumClient: BitcoinDevKit.ElectrumClient?
    var connection: BitcoinDevKit.Connection?
    var bdkWalletIsScanning = false
    var bdkWalletHasBeenScanned = false
    
    // General
    private let storageManager = LightningStorage()
    var xpub = ""
    var coreVC:CoreViewController?
    
    // Event listener
    private var eventListener: Task<Void, Never>?
    
    // Shared
    class var shared: BitcoinManager {
        struct Singleton {
            static let instance = BitcoinManager(network: EnvironmentConfig.ldkNetwork)
        }
        return Singleton.instance
    }
    
    init(network: LDKNode.Network) {
        self.network = network
    }
    
    deinit {
        self.cancelEventListener()
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
    
    func getNewMnemonic() -> String {
        // New mnemonic.
        Log.info("Creating a new mnemonic.")
        let newMnemonic:String = LDKNode.generateEntropyMnemonic(wordCount: .words12).description
        CacheManager.storeMnemonic(newMnemonic)
        return newMnemonic
    }
    
    func didGetLatestBlockHeight() async -> Bool {
        
        var receivedDictionary:NSDictionary
        do {
            receivedDictionary = try await withCheckedThrowingContinuation { continuation in
                Task {
                    let blockHeightURL = "\(EnvironmentConfig.explorerURL)/api/blocks/tip/height"
                    await CallsManager.makeApiCall(url: blockHeightURL, parameters: nil, getOrPost: .get) { result in
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
            Log.info("Could not download latest block height.")
            return false
        }
        
        if let blockHeight = receivedDictionary["result"] as? Int {
            Log.info("Block height: \(blockHeight)")
            self.coreVC?.bittrWallet.currentHeight = blockHeight
            CacheManager.updateCachedData(data: blockHeight, key: "height")
            return true
        } else {
            DispatchQueue.main.async {
                SentrySDK.capture(message: "Could not get latest block height. \(receivedDictionary)") { scope in
                    scope.setExtra(value: "BitcoinManager row 377", key: "context")
                }
            }
            Log.info("Could not download latest block height.")
            return false
        }
    }
    
    func handleError(error:Error, row:Int) {
        Log.info("Some error occurred. \(error.localizedDescription)")
        DispatchQueue.main.async {
            SentrySDK.capture(error: error) { scope in
                scope.setExtra(value: "BitcoinManager row \(row)", key: "context")
            }
            SentrySDK.metrics.count(key: "sync.walletsync.failure")
        }
    }
    
    
    func connectToLightningPeer() async -> Bool {
        
        let didEstablishPeerConnection = await self.didEstablishPeerConnection()
        
        if !didEstablishPeerConnection {
            do {
                let nodeId = EnvironmentConfig.lightningNodeId
                try self.ldkNode?.disconnect(nodeId: nodeId)
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
        
        return didEstablishPeerConnection
    }
    
    
    func didEstablishPeerConnection() async -> Bool {
        
        return await withTaskGroup(of: Bool.self) { group -> Bool in
            
            // Peer connection task.
            group.addTask {
                do {
                    try await self.connect(
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
    
    func stop() throws {
        self.cancelEventListener()
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
        
        guard let actualLdkNode = self.ldkNode else {
            throw NSError(domain: "NodeUnavailable", code: 0, userInfo: [NSLocalizedDescriptionKey: "Lightning node is not available."])
        }

        let bytes = [UInt8](data)
        let signedMessage = actualLdkNode.signMessage(msg: bytes)

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

    /// Whether it is safe to wipe the wallet from the device.
    ///
    /// Returns true only when there are no open channels AND no closed-channel
    /// funds are still settling on-chain. Wiping before this is true deletes
    /// the LDK channel state (channel monitors) needed to sweep those funds —
    /// and a BIP39 seed alone CANNOT reconstruct it. For a force-closed channel
    /// the to_local output is locked behind a CSV delay (~1 day) and only swept
    /// once it expires, so wiping early means permanent loss.
    ///
    /// If the node isn't running we can't verify the state, so we return false
    /// (refuse the wipe) rather than risk it.
    func channelsFullyClosedAndSwept() -> Bool {
        guard let node = self.ldkNode else { return false }
        let balances = node.listBalances()
        return self.listChannels().isEmpty
            && balances.totalLightningBalanceSats == 0
            && balances.pendingBalancesFromChannelClosures.isEmpty
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
               self.getEsploraClient() != nil &&
               self.ldkNode != nil ) else {
            completion(false)
            return
        }
        
        DispatchQueue.global(qos: .background).async {
            Log.info("Will light sync wallet.")
            
            // Light sync BDK.
            _ = self.lightSyncBdkWallet()
            
            // Check if any changes have been found.
            if self.coreVC!.bittrWallet.satoshisOnchain != Int(self.ldkNode!.listBalances().totalOnchainBalanceSats) || self.coreVC!.bittrWallet.allTransactions.count != self.listPayments().count {
                Log.info("Did find updates in light sync.")
                
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
    
    func getInvoice(amountMsat: UInt64, description:String, expirySecs:UInt32) async -> Bolt11Invoice? {
        do {
            let invoice = try await self.receivePayment(
                amountMsat: amountMsat,
                description: description,
                expirySecs: expirySecs)
            Log.info("Did create invoice.")
            return invoice
        } catch {
            Log.info("Couldn't create invoice.")
            DispatchQueue.main.async {
                SentrySDK.capture(error: error) { scope in
                    scope.setExtra(value: "BitcoinManager row 470", key: "context")
                }
            }
            return nil
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
    
    func sendPayment(invoice: Bolt11Invoice) throws -> PaymentHash {
        let paymentHash = try self.ldkNode!.bolt11Payment().send(invoice: invoice, routeParameters: nil)
        return paymentHash
    }
    
    func sendZeroAmountPayment(invoice: Bolt11Invoice, amount:Int) throws -> PaymentHash {
        let paymentHash = try self.ldkNode!.bolt11Payment().sendUsingAmount(invoice: invoice, amountMsat: UInt64(amount*1000), routeParameters: nil)
        return paymentHash
    }
    
    func sendBolt12Payment(offer:LDKNode.Offer, amount:Int) throws -> PaymentId? {
        let maxFeeMsat = ((amount*1000)/100) + 50_000 // 1% of amount, plus 50 satoshis.
        let routeConfig = RouteParametersConfig(
            maxTotalRoutingFeeMsat: UInt64(maxFeeMsat),
            maxTotalCltvExpiryDelta: 1008,
            maxPathCount: 10,
            maxChannelSaturationPowerOfHalf: 2)
        let paymentId = try self.ldkNode!.bolt12Payment().sendUsingAmount(offer: offer, amountMsat: UInt64(amount*1000), quantity: nil, payerNote: nil, routeParameters: routeConfig)
        return paymentId
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
        self.cancelEventListener()
        
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
    
        self.eventListener?.cancel()
        self.eventListener = Task { [weak self] in
            guard let self else { return }
            
            while !Task.isCancelled {
                let event = await self.ldkNode!.nextEventAsync()
                if Task.isCancelled { break }
                await MainActor.run {
                    self.coreVC?.ldkEventReceived(event: event)
                }
                
                try? self.ldkNode!.eventHandled()
            }
        }
    }
    
    func cancelEventListener() {
        self.eventListener?.cancel()
        self.eventListener = nil
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
    
    func defaultBip84SigningPath(addressIndex: Int = 0, account: Int = 0, change: Int = 0) -> String {
        let coinType = EnvironmentConfig.isDevelopment ? 1 : 0
        return "m/84'/\(coinType)'/\(account)'/\(change)/\(addressIndex)"
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
