//
//  LightningNodeService.swift
//  bittr
//
//  Created by Tom Melters on 18/07/2023.
//

import Foundation
import LDKNode
import BitcoinDevKit
import LDKNodeFFI
import Sentry
import CryptoKit

class LightningNodeService {
    
    public var ldkNode: Node?
    private var network: LDKNode.Network
    private let storageManager = LightningStorage()
    private var connection: Connection?
    private var electrumClient: ElectrumClient?
    private var bdkWallet: BitcoinDevKit.Wallet?
    private var xpub = ""
    private var didProceedBeyondPeerConnection = false
    private var coreVC:CoreViewController?
    
    class var shared: LightningNodeService {
        struct Singleton {
            static let instance = LightningNodeService(network: EnvironmentConfig.ldkNetwork)
        }
        return Singleton.instance
    }
    
    init(network: LDKNode.Network) {
        self.network = network
    }
    
    func start() async throws {
        
        try? FileManager.deleteLDKNodeLogLatestFile()
        
        let correctListeningAddresses = EnvironmentConfig.isDevelopment ? ["0.0.0.0:19735"] : ["0.0.0.0:9735"]
        
        let config = Config(
            storageDirPath: storageManager.getDocumentsDirectory(),
            network: network,
            listeningAddresses: correctListeningAddresses,
            announcementAddresses: nil,
            nodeAlias: nil,
            trustedPeers0conf: [EnvironmentConfig.lightningNodeId],
            probingLiquidityLimitMultiplier: UInt64(3),
            anchorChannelsConfig: AnchorChannelsConfig(
                trustedPeersNoReserve: [ PublicKey(EnvironmentConfig.lightningNodeId) ],
                perChannelReserveSats: UInt64(1000)),
            sendingParameters: nil
        )
        
        // Check if mnenomic has already been created.
        var mnemonicString = CacheManager.getMnemonic() ?? ""
        if mnemonicString == "" {
            // New wallet.
            print("Did not find mnemonic. Creating a new one.")
            mnemonicString = BitcoinDevKit.Mnemonic(wordCount: .words12).description
            CacheManager.storeMnemonic(mnemonic: mnemonicString)
        }
        
        let nodeBuilder = Builder.fromConfig(config: config)
        nodeBuilder.setEntropyBip39Mnemonic(mnemonic: mnemonicString, passphrase: "")
        
        switch network {
        case .bitcoin:
            nodeBuilder.setGossipSourceRgs(rgsServerUrl: EnvironmentConfig.RGSServerURLs.bitcoin)
            nodeBuilder.setChainSourceEsplora(serverUrl: EnvironmentConfig.EsploraURLs.bitcoinMempoolspace, config: nil)
        case .regtest:
            nodeBuilder.setChainSourceEsplora(serverUrl: EnvironmentConfig.EsploraURLs.regtest, config: nil)
        case .signet:
            nodeBuilder.setChainSourceEsplora(serverUrl: EnvironmentConfig.EsploraURLs.signet, config: nil)
        case .testnet:
            nodeBuilder.setGossipSourceRgs(rgsServerUrl: EnvironmentConfig.RGSServerURLs.testnet)
            nodeBuilder.setChainSourceEsplora(serverUrl: EnvironmentConfig.EsploraURLs.testnet, config: nil)
        }
        
        let ldkNode = try nodeBuilder.build()
        try ldkNode.start()
        self.ldkNode = ldkNode
    }
    
    func startBDK(coreViewController:CoreViewController?) {
        
        if self.coreVC == nil, coreViewController != nil {
            self.coreVC = coreViewController
        }
        
        DispatchQueue.global(qos: .background).async {
            
            // BDK launch.
            do {
                if self.bdkWallet == nil {
                    print("Will start blockchain and wallet.")
                    
                    // Attempt to create a mnemonic object from the provided mnemonic string.
                    let mnemonic = try BitcoinDevKit.Mnemonic.fromString(mnemonic: CacheManager.getMnemonic()!)
                    
                    // Create a BIP32 extended root key using the mnemonic and a nil password
                    let bip32ExtendedRootKey = DescriptorSecretKey(network: EnvironmentConfig.isDevelopment ? .regtest : .bitcoin, mnemonic: mnemonic, password: nil)
                    
                    // Create a BIP84 external descriptor using the BIP32 extended root key, specifying the keychain as external and the network as testnet
                    let bip84ExternalDescriptor = Descriptor.newBip84(secretKey: bip32ExtendedRootKey, keychain: .external, network: EnvironmentConfig.isDevelopment ? .regtest : .bitcoin)
                    
                    // Get XPUB.
                    let descriptor = bip84ExternalDescriptor.description
                    let components = descriptor.components(separatedBy: "]")
                    if components.count > 1 {
                        let xpubPart = components[1].split(separator: "/").first
                        if let xpub = xpubPart {
                            print("Did get XPUB.")
                            self.xpub = String(xpub)
                        } else {
                            print("Error: Could not extract XPUB")
                        }
                    } else {
                        print("Error: Descriptor format not recognized")
                    }
                    
                    // Create a BIP84 internal descriptor using the same BIP32 extended root key, specifying the keychain as internal and the network as testnet
                    let bip84InternalDescriptor = Descriptor.newBip84(secretKey: bip32ExtendedRootKey, keychain: .internal, network: EnvironmentConfig.bitcoinDevKitNetwork)
                    
                    // Initialize a wallet instance using the BIP84 external and internal descriptors, testnet network, and SQLite database configuration
                    var wallet:Wallet
                    self.connection = try Connection.createConnection()
                    if self.connection == nil {
                        print("Could not create connection.")
                        return
                    }
                    
                    wallet = try Wallet(descriptor: bip84ExternalDescriptor, changeDescriptor: bip84InternalDescriptor, network: EnvironmentConfig.bitcoinDevKitNetwork, connection: self.connection!)
                    self.bdkWallet = wallet
                    
                    // Configure and create an Electrum blockchain connection to interact with the Bitcoin network
                    let electrum = try ElectrumClient(url: EnvironmentConfig.electrumURL)
                    self.electrumClient = electrum
                    
                    print("Did initiate wallet and blockchain.")
                    DispatchQueue.main.async {
                        self.coreVC?.updateSync(action: "complete", type: "bdk")
                        self.coreVC?.updateSync(action: "start", type: "sync")
                    }
                }
                
                print("Will sync wallet.")
                // Synchronize the wallet with the blockchain, ensuring transaction data is up to date.
                let syncRequest = try self.bdkWallet!.startFullScan().build()
                let update = try self.electrumClient!.fullScan(
                    request: syncRequest,
                    stopGap: UInt64(25),
                    batchSize: UInt64(25),
                    fetchPrevTxouts: true
                )
                try self.bdkWallet!.applyUpdate(update: update)
                print("Wallet persist: \(try self.bdkWallet!.persist(connection: self.connection!))")
                
                print("Did sync wallet.")
                DispatchQueue.main.async {
                    self.coreVC?.updateSync(action: "complete", type: "sync")
                    self.coreVC?.updateSync(action: "start", type: "final")
                }
                
                // Uncomment the following lines to get the on-chain balance (although LDK also does that
                // Get the confirmed balance from the wallet
                self.coreVC?.bittrWallet.satoshisOnchain = Int(self.bdkWallet!.balance().total.toSat())
                print("Did fetch onchain balance.")
                
                // Retrieve a list of transaction details from the wallet, excluding raw transaction data.
                self.coreVC?.bittrWallet.transactionsOnchain = self.bdkWallet!.transactions().sorted { (tx1, tx2) in
                    return tx1.chainPosition.isBefore(tx2.chainPosition)
                }
                print("Did fetch onchain transactions.")
                
                // Get current height.
                self.coreVC?.bittrWallet.currentHeight = Int(try self.getEsploraClient()!.getHeight())
                print("Current height: \(self.coreVC?.bittrWallet.currentHeight ?? 0)")
                
                // Proceed to next step.
                Task {
                    if try await LightningNodeService.shared.listPeers().count == 1 {
                        // We're already connected to peer.
                        DispatchQueue.global(qos: .background).async {
                            self.didProceedBeyondPeerConnection = true
                            self.getChannelsAndPayments()
                        }
                    } else {
                        // Connect to peer.
                        DispatchQueue.global(qos: .background).async {
                            self.connectToLightningPeer()
                        }
                    }
                }
                
            } catch {
                print("Some error occurred. \(error.localizedDescription)")
                self.coreVC?.stopLightning(message: error.localizedDescription, stopNode: false)
                SentrySDK.capture(error: error)
            }
        }
    }
    
    
    func connectToLightningPeer() {
        
        self.didProceedBeyondPeerConnection = false
        
        // Connect to Lightning peer.
        let nodeId = EnvironmentConfig.lightningNodeId
        let address = EnvironmentConfig.lightningNodeAddress
        
        let connectTask = Task {
            do {
                try await LightningNodeService.shared.connect(
                    nodeId: nodeId,
                    address: address,
                    persist: true
                )
                try Task.checkCancellation()
                if Task.isCancelled == true {
                    print("Did connect to peer, but too late.")
                    return false
                }
                print("Did connect to peer.")
                return true
            } catch let error as NodeError {
                let errorString = handleNodeError(error)
                DispatchQueue.main.async {
                    // Handle UI error showing here, like showing an alert
                    print("Can't connect to peer. Error message: \(errorString.title), \(errorString.detail)")
                    SentrySDK.capture(error: error)
                }
                return false
            } catch {
                DispatchQueue.main.async {
                    // Handle UI error showing here, like showing an alert
                    print("Can't connect to peer: No error message.")
                    SentrySDK.capture(error: error)
                }
                return false
            }
        }
        
        let timeoutTask = Task {
            try await Task.sleep(nanoseconds: UInt64(5) * NSEC_PER_SEC)
            connectTask.cancel()
            print("Connecting to peer takes too long.")
            do {
                try LightningNodeService.shared.ldkNode?.disconnect(nodeId: nodeId)
                DispatchQueue.main.async {
                    print("Did disconnect from peer.")
                    if !self.didProceedBeyondPeerConnection {
                        self.getChannelsAndPayments()
                        self.didProceedBeyondPeerConnection = true
                    }
                }
            } catch let error as NodeError {
                let errorString = handleNodeError(error)
                DispatchQueue.main.async {
                    print("Can't disconnect from peer: \(errorString)")
                    if !self.didProceedBeyondPeerConnection {
                        self.getChannelsAndPayments()
                        self.didProceedBeyondPeerConnection = true
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    print("Can't disconnect from peer: No error message.")
                    if !self.didProceedBeyondPeerConnection {
                        self.getChannelsAndPayments()
                        self.didProceedBeyondPeerConnection = true
                    }
                }
            }
        }
        
        Task.init {
            let result = await connectTask.value
            timeoutTask.cancel()
            if result == true {
                // Could connect to peer.
                if !self.didProceedBeyondPeerConnection {
                    self.getChannelsAndPayments()
                    self.didProceedBeyondPeerConnection = true
                }
            } else {
                // Couldn't connect to peer.
                if !self.didProceedBeyondPeerConnection {
                    self.getChannelsAndPayments()
                    self.didProceedBeyondPeerConnection = true
                }
            }
        }
    }
    
    
    func getChannelsAndPayments() {
        
        Task {
            do {
                // Get channels.
                let channels = try await LightningNodeService.shared.listChannels()
                print("Channels: \(channels.count)")
                
                // Register funding transaction ID.
                if channels.count > 0 {
                    if let channelTxoID = channels[0].fundingTxo?.txid as? String {
                        CacheManager.storeTxoID(txoID: channelTxoID)
                    }
                }
                
                // Get payments.
                var payments = try await LightningNodeService.shared.listPayments()
                // Remove onchain payments from array.
                for (index, eachPayment) in payments.enumerated().reversed() {
                    switch eachPayment.kind {
                    case .onchain(txid: _, status: _): payments.remove(at: index)
                    default: break
                    }
                }
                
                // Send notification with all details.
                DispatchQueue.main.async {
                    self.coreVC?.bittrWallet.lightningChannels = channels
                    self.coreVC?.bittrWallet.transactionsLightning = payments
                    self.coreVC?.homeVC?.loadWalletData()
                }
            } catch {
                print("Error listing channels: \(error.localizedDescription)")
            }
        }
    }
    
    func stop() throws {
        if let actualLdkNode = ldkNode {
            try actualLdkNode.stop()
        }
    }
    
    func nodeId() -> String {
        let nodeID = ldkNode!.nodeId()
        return nodeID
    }
    
    func signMessage(message: String) async throws -> String {
        guard let data = message.data(using: .utf8) else {
            throw NSError(domain: "InvalidInput", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid input string. Couldn't convert to UTF8 data."])
        }
        
        let bytes = [UInt8](data)
        let signedMessage = try ldkNode!.signMessage(msg: bytes)
        
        return signedMessage
    }
    
    func listPeers() async throws -> [PeerDetails] {
        let peers = ldkNode!.listPeers()
        return peers
    }
    
    func listPayments() async throws -> [PaymentDetails] {
        let payments = ldkNode!.listPayments()
        return payments
    }
    
    func listChannels() async throws -> [LDKNode.ChannelDetails] {
        let channels = ldkNode!.listChannels()
        return channels
    }
    
    func connect(nodeId: PublicKey, address: String, persist: Bool) async throws {
        try ldkNode!.connect(
            nodeId: nodeId,
            address: address,
            persist: persist
        )
    }
    
    func lightSync(force:Bool, completion: @escaping (Bool) -> Void) {
        
        DispatchQueue.global(qos: .background).async {
            do {
                print("Will light sync wallet.")
                // Synchronize the wallet with the blockchain, ensuring transaction data is up to date.
                let syncRequest = try self.bdkWallet!.startSyncWithRevealedSpks().build()
                let update = try self.electrumClient!.sync(
                    request: syncRequest,
                    batchSize: UInt64(25),
                    fetchPrevTxouts: true
                )
                try self.bdkWallet!.applyUpdate(update: update)
                let _ = try self.bdkWallet!.persist(connection: self.connection!)
                
                if force || self.coreVC!.bittrWallet.satoshisOnchain != Int(self.bdkWallet!.balance().total.toSat()) {
                    
                    self.coreVC!.bittrWallet.satoshisOnchain = Int(self.bdkWallet!.balance().total.toSat())
                    self.coreVC?.bittrWallet.currentHeight = Int(try self.getEsploraClient()!.getHeight())
                    self.coreVC!.bittrWallet.transactionsOnchain = self.bdkWallet!.transactions().sorted { (tx1, tx2) in
                        return tx1.chainPosition.isBefore(tx2.chainPosition)
                    }
                    
                    DispatchQueue.main.async {
                        self.coreVC!.homeVC!.loadWalletData()
                        self.coreVC!.homeVC!.moveVC?.updateLabels()
                        completion(true)
                    }
                } else {
                    DispatchQueue.main.async { completion(false) }
                }
            } catch {
                print("Error completing light sync: \(error.localizedDescription)")
                DispatchQueue.main.async { completion(false) }
            }
        }
    }
    
    func syncWallets() throws {
        try ldkNode!.syncWallets()
    }
    
    func getWallet() -> BitcoinDevKit.Wallet? {
        return bdkWallet
    }
    
    func getXpub() -> String {
        return xpub
    }
    
    func walletReset() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            self.startBDK(coreViewController: nil)
        }
    }
    
    func receivePayment(amountMsat: UInt64, description: String, expirySecs: UInt32) async throws -> Bolt11Invoice {
        let invoiceDescription = Bolt11InvoiceDescription.direct(description: description)
        let invoice = try ldkNode!.bolt11Payment().receive(amountMsat: amountMsat, description: invoiceDescription, expirySecs: expirySecs)
        return invoice
    }
    
    func receivePaymentWithHash(amountMsat: UInt64, descriptionHash: String, expirySecs: UInt32) async throws -> Bolt11Invoice {
        let invoiceDescription = Bolt11InvoiceDescription.hash(hash: descriptionHash)
        let invoice = try ldkNode!.bolt11Payment().receive(amountMsat: amountMsat, description: invoiceDescription, expirySecs: expirySecs)
        return invoice
    }
    
    func sendPayment(invoice: Bolt11Invoice) async throws -> PaymentHash {
        let paymentHash = try ldkNode!.bolt11Payment().send(invoice: invoice, sendingParameters: nil)
        return paymentHash
    }
    
    func sendZeroAmountPayment(invoice: Bolt11Invoice, amount:Int) async throws -> PaymentHash {
        let paymentHash = try ldkNode!.bolt11Payment().sendUsingAmount(invoice: invoice, amountMsat: UInt64(amount*1000), sendingParameters: nil)
        return paymentHash
    }
    
    func getPaymentDetails(paymentHash: PaymentHash) -> PaymentDetails? {
        if let invoiceDetails = ldkNode!.payment(paymentId: paymentHash) {
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
        print("🔍 [DEBUG] LightningNodeService - Resetting node state")
        
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
        self.didProceedBeyondPeerConnection = false
        
        print("🔍 [DEBUG] LightningNodeService - Node state reset completed")
    }
    
    func listenForEvents() {
        
        DispatchQueue.global(qos: .background).async {
            let event = self.ldkNode!.waitNextEvent()
            self.coreVC?.ldkEventReceived(event: event)
            
            do {
                try self.ldkNode!.eventHandled()
            } catch {
                print("Error: \(error.localizedDescription)")
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

extension ChainPosition {
    func isBefore(_ other: ChainPosition) -> Bool {
        switch (self, other) {
        case (.unconfirmed, .confirmed):
            // Unconfirmed should come before confirmed.
            return true
        case (.confirmed, .unconfirmed):
            // Confirmed should come after unconfirmed.
            return false
        case (.unconfirmed(let timestamp1), .unconfirmed(let timestamp2)):
            // If both are unconfirmed, compare by timestamp (optional).
            return (timestamp1 ?? 0) < (timestamp2 ?? 0)
        case (
            .confirmed(let blockTime1, let transitively1),
            .confirmed(let blockTime2, let transitively2)
        ):
            // Sort by height descending, but note that if transitively is Some,
            // this block height might not be the "original" confirmation block
            return blockTime1.blockId.height != blockTime2.blockId.height
                ? blockTime1.blockId.height > blockTime2.blockId.height
                : (transitively1 != nil) && (transitively2 == nil)
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
