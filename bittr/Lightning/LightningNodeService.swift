//
//  LightningNodeService.swift
//  bittr
//
//  Created by Tom Melters on 18/07/2023.
//

import Foundation
import LDKNode
import BitcoinDevKit
import bdkFFI
import LDKNodeFFI
import Sentry

class LightningNodeService {
    public var ldkNode: Node?
    private var network: LDKNode.Network
    private let mnemonicKey = ""
    private let storageManager = LightningStorage()
    private var bdkWallet: BitcoinDevKit.Wallet?
    private var blockchain: Blockchain?
    private var xpub = ""
    private var bdkBalance = 0
    private var varWalletTransactions = [TransactionDetails]()
    private var varMnemonicString = ""
    private var currentHeight = 0
    private var didProceedBeyondPeerConnection = false
    
    // In order to switch between Development and Production, change the network here between .testnet and .bitcoin. ALSO change devEnvironment in CoreViewController between 0 for Dev and 1 for Production.
    class var shared: LightningNodeService {
        struct Singleton {
            static let instance = LightningNodeService(network: .bitcoin)
        }
        return Singleton.instance
    }
    
    
    init(network: LDKNode.Network) {
        self.network = network
    }
    
    func start() async throws {
        
        try? FileManager.deleteLDKNodeLogLatestFile()
        
        // TODO: Public?
        var correctListeningAddresses = ["0.0.0.0:9735"]
        if UserDefaults.standard.value(forKey: "envkey") as? Int == 0 {
            correctListeningAddresses = ["0.0.0.0:19735"]
        }
        
        let config = Config(
            storageDirPath: storageManager.getDocumentsDirectory(),
            logDirPath: storageManager.getDocumentsDirectory(),
            network: network,
            listeningAddresses: correctListeningAddresses,
            defaultCltvExpiryDelta: UInt32(144),
            onchainWalletSyncIntervalSecs: UInt64(60),
            walletSyncIntervalSecs: UInt64(20),
            feeRateCacheUpdateIntervalSecs: UInt64(600),
            // TODO: Public? // Signet and Bitcoin node.
            trustedPeers0conf: ["03c94d19734a7808a333bba797a6ffe30a745609d7cd049cf4f5e4685e85ca6f36", "036956f49ef3db863e6f4dc34f24ace19be177168a0870e83fcaf6e7a683832b12"],
            probingLiquidityLimitMultiplier: UInt64(3),
            logLevel: .debug,
            anchorChannelsConfig: AnchorChannelsConfig(
                    trustedPeersNoReserve: [
                        PublicKey("03c94d19734a7808a333bba797a6ffe30a745609d7cd049cf4f5e4685e85ca6f36"),
                        PublicKey("036956f49ef3db863e6f4dc34f24ace19be177168a0870e83fcaf6e7a683832b12")
                    ],
                    perChannelReserveSats: UInt64(1000) // Set an appropriate value
                )
        )
        
        let nodeBuilder = Builder.fromConfig(config: config)
        
        // Check if mnenomic has already been created.
        var mnemonicString = ""
        if let actualMnemonic = CacheManager.getMnemonic() {
            // Mnemonic found in storage.
            mnemonicString = actualMnemonic
            print("Did find mnemonic.")
        } else {
            // Create new mnemonic.
            let mnemonic = BitcoinDevKit.Mnemonic.init(wordCount: .words12)
            mnemonicString = mnemonic.asString()
            print("Did not find mnemonic. Creating a new one.")
            CacheManager.storeMnemonic(mnemonic: mnemonicString)
        }
        
        self.varMnemonicString = mnemonicString
        
        nodeBuilder.setEntropyBip39Mnemonic(mnemonic: mnemonicString, passphrase: "")
        
        switch network {
        case .bitcoin:
            nodeBuilder.setGossipSourceRgs(rgsServerUrl: Constants.Config.RGSServerURLNetwork.bitcoin)
            nodeBuilder.setEsploraServer(esploraServerUrl: Constants.Config.EsploraServerURLNetwork.Bitcoin.bitcoin_mempoolspace)
        case .regtest:
            nodeBuilder.setEsploraServer(esploraServerUrl: Constants.Config.EsploraServerURLNetwork.regtest)
        case .signet:
            nodeBuilder.setEsploraServer(esploraServerUrl: Constants.Config.EsploraServerURLNetwork.signet)
        case .testnet:
            nodeBuilder.setGossipSourceRgs(rgsServerUrl: Constants.Config.RGSServerURLNetwork.testnet)
            nodeBuilder.setEsploraServer(esploraServerUrl: Constants.Config.EsploraServerURLNetwork.testnet)
        }
        
        let ldkNode = try nodeBuilder.build()
        try ldkNode.start()
        self.ldkNode = ldkNode
    }
    
    func startBDK() {
        
        DispatchQueue.global(qos: .background).async {
            
            var walletTransactions:[TransactionDetails]?
            
            // BDK launch.
            do {
                
                if self.blockchain == nil || self.bdkWallet == nil {
                    print("Will start blockchain and wallet.")
                    // Attempt to create a mnemonic object from the provided mnemonic string.
                    let mnemonic = try BitcoinDevKit.Mnemonic.fromString(mnemonic: self.varMnemonicString)
                    
                    // Create a BIP32 extended root key using the mnemonic and a nil password
                    var bip32ExtendedRootKey:DescriptorSecretKey
                    if UserDefaults.standard.value(forKey: "envkey") as? Int == 0 {
                        bip32ExtendedRootKey = DescriptorSecretKey(network: .testnet, mnemonic: mnemonic, password: nil)
                    } else {
                        bip32ExtendedRootKey = DescriptorSecretKey(network: .bitcoin, mnemonic: mnemonic, password: nil)
                    }
                    
                    // Create a BIP84 external descriptor using the BIP32 extended root key, specifying the keychain as external and the network as testnet
                    var bip84ExternalDescriptor:Descriptor
                    if UserDefaults.standard.value(forKey: "envkey") as? Int == 0 {
                        bip84ExternalDescriptor = Descriptor.newBip84(secretKey: bip32ExtendedRootKey, keychain: .external, network: .testnet)
                    } else {
                        bip84ExternalDescriptor = Descriptor.newBip84(secretKey: bip32ExtendedRootKey, keychain: .external, network: .bitcoin)
                    }
                    
                    let descriptor = bip84ExternalDescriptor.asString()
                    
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
                    var bip84InternalDescriptor:Descriptor
                    if UserDefaults.standard.value(forKey: "envkey") as? Int == 0 {
                        bip84InternalDescriptor = Descriptor.newBip84(secretKey: bip32ExtendedRootKey, keychain: .internal, network: .testnet)
                    } else {
                        bip84InternalDescriptor = Descriptor.newBip84(secretKey: bip32ExtendedRootKey, keychain: .internal, network: .bitcoin)
                    }
                    
                    // Set up the local SQLite database for the Bitcoin wallet using the provided file path
                    let dbPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!.appendingPathComponent("bitcoin_wallet.sqlite")
                    let config = SqliteDbConfiguration(path: dbPath.path)
                    
                    // Initialize a wallet instance using the BIP84 external and internal descriptors, testnet network, and SQLite database configuration
                    var wallet:Wallet
                    if UserDefaults.standard.value(forKey: "envkey") as? Int == 0 {
                        wallet = try BitcoinDevKit.Wallet.init(descriptor: bip84ExternalDescriptor, changeDescriptor: bip84InternalDescriptor, network: .testnet, databaseConfig: .sqlite(config: config))
                    } else {
                        wallet = try BitcoinDevKit.Wallet.init(descriptor: bip84ExternalDescriptor, changeDescriptor: bip84InternalDescriptor, network: .bitcoin, databaseConfig: .sqlite(config: config))
                    }
                    self.bdkWallet = wallet
                    
                    // TODO: Public?
                    // Configure and create an Electrum blockchain connection to interact with the Bitcoin network
                    var electrumUrl = "ssl://electrum.blockstream.info:50002"
                    if UserDefaults.standard.value(forKey: "envkey") as? Int == 0 {
                        electrumUrl = "ssl://electrum.blockstream.info:60002"
                    }
                    let electrum = ElectrumConfig(url: electrumUrl, socks5: nil, retry: 5, timeout: nil, stopGap: 10, validateDomain: true)
                    let blockchainConfig = BlockchainConfig.electrum(config: electrum)
                    let blockchain = try Blockchain(config: blockchainConfig)
                    self.blockchain = blockchain
                    
                    print("Did initiate wallet and blockchain.")
                    DispatchQueue.main.async {
                        let notificationDict:[String: Any] = ["action":"complete","type":"bdk"]
                        NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "updatesync"), object: nil, userInfo: notificationDict) as Notification)
                        let notificationDict2:[String: Any] = ["action":"start","type":"sync"]
                        NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "updatesync"), object: nil, userInfo: notificationDict2) as Notification)
                    }
                }
                
                print("Will sync wallet.")
                
                // Synchronize the wallet with the blockchain, ensuring transaction data is up to date
                try self.bdkWallet!.sync(blockchain: self.blockchain!, progress: nil)
                
                print("Did sync wallet.")
                DispatchQueue.main.async {
                    let notificationDict3:[String: Any] = ["action":"complete","type":"sync"]
                    NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "updatesync"), object: nil, userInfo: notificationDict3) as Notification)
                    let notificationDict4:[String: Any] = ["action":"start","type":"final"]
                    NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "updatesync"), object: nil, userInfo: notificationDict4) as Notification)
                }
                
                // Uncomment the following lines to get the on-chain balance (although LDK also does that
                // Get the confirmed balance from the wallet
                self.bdkBalance = Int(try self.bdkWallet!.getBalance().confirmed)
                print("Did fetch onchain balance from BDK.")
                
                // Retrieve a list of transaction details from the wallet, excluding raw transaction data
                walletTransactions = try self.bdkWallet!.listTransactions(includeRaw: false)
                
                // Print the balance and the list of wallet transactions
                print("Did fetch BDK transactions.")
                
                let actualWalletTransactions = walletTransactions ?? [TransactionDetails]()
                self.varWalletTransactions = actualWalletTransactions
                
                let fetchedCurrentHeight = try self.blockchain!.getHeight()
                self.currentHeight = Int(fetchedCurrentHeight)
                
                self.connectToLightningPeer()
                
            } catch let error as BdkError {
                print("Some error occurred. \(error)")
                let notificationDict:[String: Any] = ["message":"We can't seem to connect to the Blockchain. Please check your network."]
                NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "stoplightning"), object: nil, userInfo: notificationDict) as Notification)
                SentrySDK.capture(error: error)
            } catch {
                print("Some error occurred. \(error.localizedDescription)")
                let notificationDict:[String: Any] = ["message":"\(error.localizedDescription)"]
                NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "stoplightning"), object: nil, userInfo: notificationDict) as Notification)
                SentrySDK.capture(error: error)
            }
        }
    }
    
    
    func connectToLightningPeer() {
        
        self.didProceedBeyondPeerConnection = false
        
        // TODO: Public?
        // .testnet and .bitcoin
        let nodeIds = ["026d74bf2a035b8a14ea7c59f6a0698d019720e812421ec02762fdbf064c3bc326", "036956f49ef3db863e6f4dc34f24ace19be177168a0870e83fcaf6e7a683832b12"]
        let addresses = ["109.205.181.232:9735", "86.104.228.24:9735"]
        
        // Connect to Lightning peer.
        let nodeId = nodeIds[UserDefaults.standard.value(forKey: "envkey") as? Int ?? 1] // Extract this from your peer string
        let address = addresses[UserDefaults.standard.value(forKey: "envkey") as? Int ?? 1] // Extract this from your peer string
        
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
                        self.getChannelsAndPayments(actualWalletTransactions: self.varWalletTransactions)
                        self.didProceedBeyondPeerConnection = true
                    }
                }
            } catch let error as NodeError {
                let errorString = handleNodeError(error)
                DispatchQueue.main.async {
                    print("Can't disconnect from peer: \(errorString)")
                    if !self.didProceedBeyondPeerConnection {
                        self.getChannelsAndPayments(actualWalletTransactions: self.varWalletTransactions)
                        self.didProceedBeyondPeerConnection = true
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    print("Can't disconnect from peer: No error message.")
                    if !self.didProceedBeyondPeerConnection {
                        self.getChannelsAndPayments(actualWalletTransactions: self.varWalletTransactions)
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
                    self.getChannelsAndPayments(actualWalletTransactions: self.varWalletTransactions)
                    self.didProceedBeyondPeerConnection = true
                }
            } else {
                // Couldn't connect to peer.
                if !self.didProceedBeyondPeerConnection {
                    self.getChannelsAndPayments(actualWalletTransactions: self.varWalletTransactions)
                    self.didProceedBeyondPeerConnection = true
                }
            }
        }
    }
    
    
    func getChannelsAndPayments(actualWalletTransactions:[TransactionDetails]) {
        
        // Get Lightning channels.
        Task {
            do {
                let channels = try await LightningNodeService.shared.listChannels()
                print("Channels: \(channels.count)")
                if channels.count > 0 {
                    if let channelTxoID = channels[0].fundingTxo?.txid as? String {
                        CacheManager.storeTxoID(txoID: channelTxoID)
                    }
                }
                
                let payments = try await LightningNodeService.shared.listPayments()
                
                var transactionsNotificationDict = [AnyHashable:Any]()
                transactionsNotificationDict = ["transactions":actualWalletTransactions/*,"lightningnodeservice":self*/,"channels":channels, "payments":payments, "bdkbalance":bdkBalance, "currentheight":self.currentHeight]
                
                // Step 9.
                NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "getwalletdata"), object: nil, userInfo: transactionsNotificationDict) as Notification)
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
    
    func syncWallets() throws {
        try ldkNode!.syncWallets()
    }
    
    func getWallet() -> BitcoinDevKit.Wallet? {
        return bdkWallet
    }
    
    func getBlockchain() -> Blockchain? {
        return blockchain
    }
    
    func getXpub() -> String {
        return xpub
    }
    
    func walletReset() {
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            do {
                try self.bdkWallet!.sync(blockchain: self.blockchain!, progress: nil)
                
                let actualTransactions:[TransactionDetails] = try self.bdkWallet!.listTransactions(includeRaw: false)
                Task {
                    let actualChannels = try await LightningNodeService.shared.listChannels()
                    let actualPayments = try await LightningNodeService.shared.listPayments()
                    DispatchQueue.main.async {
                        let transactionsNotificationDict:[AnyHashable:Any] = ["transactions":actualTransactions,"lightningnodeservice":self,"channels":actualChannels,"payments":actualPayments]
                        NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "getwalletdata"), object: nil, userInfo: transactionsNotificationDict) as Notification)
                    }
                }
            } catch let error as NodeError {
                let errorString = handleNodeError(error)
                print("Error getting transactions. \(errorString.title): \(errorString.detail)")
            } catch {
                print("Error getting transactions. \(error.localizedDescription)")
            }
        }
    }
    
    func receivePayment(amountMsat: UInt64, description: String, expirySecs: UInt32) async throws -> Bolt11Invoice {
        let invoice = try ldkNode!.bolt11Payment().receive(amountMsat: amountMsat, description: description, expirySecs: expirySecs)
        return invoice
    }
    
    func sendPayment(invoice: Bolt11Invoice) async throws -> PaymentHash {
        let paymentHash = try ldkNode!.bolt11Payment().send(invoice: invoice)
        return paymentHash
    }
    
    func getPaymentDetails(paymentHash: PaymentHash) -> PaymentDetails? {
        
        if let invoiceDetails = ldkNode!.payment(paymentId: paymentHash) {
            //let invoiceAmountInt = Int(invoiceAmount)
            return invoiceDetails
        } else {
            return nil
        }
    }
    
    func deleteDocuments() throws {
        try FileManager.default.deleteAllContentsInDocumentsDirectory()
    }
    
    func listenForEvents() {
        
        DispatchQueue.global(qos: .background).async {
            let event = self.ldkNode!.waitNextEvent()
            NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "ldkEventReceived"), object: nil, userInfo: ["event":event]) as Notification)
            self.ldkNode!.eventHandled()
            self.listenForEvents()
        }
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

