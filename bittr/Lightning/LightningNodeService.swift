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

class LightningNodeService {
    
    public var ldkNode: Node?
    private var network: LDKNode.Network
    private let mnemonicKey = ""
    private let storageManager = LightningStorage()
    private var connection: Connection?
    private var electrumClient: ElectrumClient?
    private var bdkWallet: BitcoinDevKit.Wallet?
    private var xpub = ""
    private var bdkBalance = 0
    private var varWalletTransactions = [CanonicalTx]()
    private var varMnemonicString = ""
    private var currentHeight = 0
    private var didProceedBeyondPeerConnection = false
    private var coreVC:CoreViewController?
    
    // In order to switch between Development and Production, change the network here between .testnet and .bitcoin. ALSO change devEnvironment in CoreViewController between 0 for Dev and 1 for Production.
    class var shared: LightningNodeService {
        struct Singleton {
            static let instance = LightningNodeService(network: .regtest)
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
            network: network,
            listeningAddresses: correctListeningAddresses,
            announcementAddresses: nil,
            nodeAlias: nil,
            trustedPeers0conf: ["02006a822bf3bd3e1cfe4acc6b333982d9218a0fbea9131add14360f0569ad17cb", "02006a822bf3bd3e1cfe4acc6b333982d9218a0fbea9131add14360f0569ad17cb"],
            probingLiquidityLimitMultiplier: UInt64(3),
            anchorChannelsConfig: AnchorChannelsConfig(
                trustedPeersNoReserve: [
                    PublicKey("02006a822bf3bd3e1cfe4acc6b333982d9218a0fbea9131add14360f0569ad17cb"),
                    PublicKey("02006a822bf3bd3e1cfe4acc6b333982d9218a0fbea9131add14360f0569ad17cb")
                ], perChannelReserveSats: UInt64(1000)),
            sendingParameters: nil
        )
        
        let nodeBuilder = Builder.fromConfig(config: config)
        
        // Check if mnenomic has already been created.
        var mnemonicString = ""
        if let actualMnemonic = CacheManager.getMnemonic() {
            // Existing wallet.
            print("Did find mnemonic.")
            mnemonicString = actualMnemonic
        } else {
            // New wallet.
            print("Did not find mnemonic. Creating a new one.")
            mnemonicString = BitcoinDevKit.Mnemonic(wordCount: .words12).description
            CacheManager.storeMnemonic(mnemonic: mnemonicString)
        }
        
        self.varMnemonicString = mnemonicString
        
        nodeBuilder.setEntropyBip39Mnemonic(mnemonic: mnemonicString, passphrase: "")
        
        switch network {
        case .bitcoin:
            nodeBuilder.setGossipSourceRgs(rgsServerUrl: Constants.Config.RGSServerURLNetwork.bitcoin)
            nodeBuilder.setChainSourceEsplora(serverUrl: Constants.Config.EsploraServerURLNetwork.Bitcoin.bitcoin_mempoolspace, config: nil)
        case .regtest:
            nodeBuilder.setChainSourceEsplora(serverUrl: Constants.Config.EsploraServerURLNetwork.regtest, config: nil)
        case .signet:
            nodeBuilder.setChainSourceEsplora(serverUrl: Constants.Config.EsploraServerURLNetwork.signet, config: nil)
        case .testnet:
            nodeBuilder.setGossipSourceRgs(rgsServerUrl: Constants.Config.RGSServerURLNetwork.testnet)
            nodeBuilder.setChainSourceEsplora(serverUrl: Constants.Config.EsploraServerURLNetwork.testnet, config: nil)
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
            
            var walletTransactions:[CanonicalTx]?
            
            // BDK launch.
            do {
                
                if /*self.blockchain == nil || */self.bdkWallet == nil {
                    
                    print("Will start blockchain and wallet.")
                    
                    // Attempt to create a mnemonic object from the provided mnemonic string.
                    let mnemonic = try BitcoinDevKit.Mnemonic.fromString(mnemonic: self.varMnemonicString)
                    
                    // Create a BIP32 extended root key using the mnemonic and a nil password
                    var bip32ExtendedRootKey:DescriptorSecretKey
                    if UserDefaults.standard.value(forKey: "envkey") as? Int == 0 {
                        bip32ExtendedRootKey = DescriptorSecretKey(network: .regtest, mnemonic: mnemonic, password: nil)
                    } else {
                        bip32ExtendedRootKey = DescriptorSecretKey(network: .bitcoin, mnemonic: mnemonic, password: nil)
                    }
                    
                    // Create a BIP84 external descriptor using the BIP32 extended root key, specifying the keychain as external and the network as testnet
                    var bip84ExternalDescriptor:Descriptor
                    if UserDefaults.standard.value(forKey: "envkey") as? Int == 0 {
                        bip84ExternalDescriptor = Descriptor.newBip84(secretKey: bip32ExtendedRootKey, keychain: .external, network: .regtest)
                    } else {
                        bip84ExternalDescriptor = Descriptor.newBip84(secretKey: bip32ExtendedRootKey, keychain: .external, network: .bitcoin)
                    }
                    
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
                    var bip84InternalDescriptor:Descriptor
                    if UserDefaults.standard.value(forKey: "envkey") as? Int == 0 {
                        bip84InternalDescriptor = Descriptor.newBip84(secretKey: bip32ExtendedRootKey, keychain: .internal, network: .regtest)
                    } else {
                        bip84InternalDescriptor = Descriptor.newBip84(secretKey: bip32ExtendedRootKey, keychain: .internal, network: .bitcoin)
                    }
                    
                    // Set up the local SQLite database for the Bitcoin wallet using the provided file path
                    //let dbPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!.appendingPathComponent("bitcoin_wallet.sqlite")
                    //let config = SqliteDbConfiguration(path: dbPath.path)
                    
                    // Initialize a wallet instance using the BIP84 external and internal descriptors, testnet network, and SQLite database configuration
                    var wallet:Wallet
                    self.connection = try Connection.createConnection()
                    if self.connection == nil {
                        print("Could not create connection.")
                        return
                    }
                    
                    if UserDefaults.standard.value(forKey: "envkey") as? Int == 0 {
                        wallet = try Wallet(descriptor: bip84ExternalDescriptor, changeDescriptor: bip84InternalDescriptor, network: .regtest, connection: self.connection!)
                    } else {
                        wallet = try Wallet(descriptor: bip84ExternalDescriptor, changeDescriptor: bip84InternalDescriptor, network: .bitcoin, connection: self.connection!)
                    }
                    self.bdkWallet = wallet
                    
                    // TODO: Public?
                    // Configure and create an Electrum blockchain connection to interact with the Bitcoin network
                    var electrumUrl = "ssl://electrum.blockstream.info:50002"
                    if UserDefaults.standard.value(forKey: "envkey") as? Int == 0 {
                        electrumUrl = "tcp://regtest.getbittr.com:19001"
                    }
                    let electrum = try ElectrumClient(url: electrumUrl)
                    self.electrumClient = electrum
                    
                    /*let electrum = ElectrumConfig(
                        url: electrumUrl,
                        socks5: nil,
                        retry: 5,
                        timeout: nil,
                        stopGap: 10,
                        validateDomain: electrumUrl.starts(with: "ssl://") // Only validate if using SSL
                    )
                    let blockchainConfig = BlockchainConfig.electrum(config: electrum)
                    let blockchain = try Blockchain(config: blockchainConfig)
                    self.blockchain = blockchain*/
                    
                    print("Did initiate wallet and blockchain.")
                    DispatchQueue.main.async {
                        self.coreVC?.updateSync(action: "complete", type: "bdk")
                        self.coreVC?.updateSync(action: "start", type: "sync")
                    }
                }
                
                print("Will sync wallet.")
                // Synchronize the wallet with the blockchain, ensuring transaction data is up to date
                //try self.bdkWallet!.sync(blockchain: self.blockchain!, progress: nil)
                let syncRequest = try self.bdkWallet!.startFullScan().build()
                //let syncRequest = try self.bdkWallet!.startSyncWithRevealedSpks().build()
                /*let update = try self.electrumClient!.sync(
                    request: syncRequest,
                    batchSize: UInt64(25),
                    fetchPrevTxouts: true
                )*/
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
                //self.bdkBalance = Int(try self.bdkWallet!.getBalance().total)
                self.bdkBalance = Int(self.bdkWallet!.balance().total.toSat())
                print("Did fetch onchain balance.")
                
                // Retrieve a list of transaction details from the wallet, excluding raw transaction data
                //walletTransactions = try self.bdkWallet!.listTransactions(includeRaw: false)
                walletTransactions = self.bdkWallet!.transactions()
                let sortedTransactions = (walletTransactions ?? [CanonicalTx]()).sorted { (tx1, tx2) in
                    return tx1.chainPosition.isBefore(tx2.chainPosition)
                }
                self.varWalletTransactions = sortedTransactions
                print("Did fetch onchain transactions.")
                
                // Get current height.
                let fetchedCurrentHeight = try self.getEsploraClient()!.getHeight()
                self.currentHeight = Int(fetchedCurrentHeight)
                print("Current height: \(self.currentHeight)")
                
                // Proceed to next step.
                Task {
                    if try await LightningNodeService.shared.listPeers().count == 1 {
                        // We're already connected to peer.
                        DispatchQueue.global(qos: .background).async {
                            self.didProceedBeyondPeerConnection = true
                            self.getChannelsAndPayments(actualWalletTransactions: self.varWalletTransactions)
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
        
        // TODO: Public?
        // .testnet and .bitcoin
        let nodeIds = ["02006a822bf3bd3e1cfe4acc6b333982d9218a0fbea9131add14360f0569ad17cb", "02006a822bf3bd3e1cfe4acc6b333982d9218a0fbea9131add14360f0569ad17cb"]
        let addresses = ["31.58.51.17:9735", "31.58.51.17:9735"]
        
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
    
    
    func getChannelsAndPayments(actualWalletTransactions:[CanonicalTx]) {
        
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
                    default: print("Lightning payment.")
                    }
                }
                
                // Send notification with all details.
                DispatchQueue.main.async {
                    self.coreVC?.homeVC?.loadWalletData(currentHeight: self.currentHeight, lightningChannels: channels, bdkBalance: self.bdkBalance, canonicalTransactions: actualWalletTransactions, paymentDetails: payments)
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
    
    func syncWallets() throws {
        try ldkNode!.syncWallets()
    }
    
    func getWallet() -> BitcoinDevKit.Wallet? {
        return bdkWallet
    }
    
    /*func getBlockchain() -> Blockchain? {
        return blockchain
    }*/
    
    func getXpub() -> String {
        return xpub
    }
    
    func walletReset() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            self.startBDK(coreViewController: nil)
        }
    }
    
    /// Lightweight wallet sync that refreshes transactions and balances without full wallet reset
    /// Use this for refreshing data after operations like swaps, payments, etc.
    /// For full wallet reset (e.g., after errors), use walletReset() instead
//    func syncWalletAndLoadTransactions() {
//        DispatchQueue.global(qos: .background).async {
//            do {
//                print("Starting lightweight wallet sync...")
//                
//                // Send notification that sync is starting
//                DispatchQueue.main.async {
//                    let notificationDict:[String: Any] = ["action":"start","type":"sync"]
//                    NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "updatesync"), object: nil, userInfo: notificationDict) as Notification)
//                }
//                
//                // Sync the wallet with the blockchain
//                if let wallet = self.bdkWallet, let blockchain = self.blockchain {
//                    try wallet.sync(blockchain: blockchain, progress: nil)
//                    print("Wallet sync completed.")
//                    
//                    // Get updated balance
//                    self.bdkBalance = Int(try wallet.getBalance().total)
//                    print("Updated onchain balance: \(self.bdkBalance)")
//                    
//                    // Get updated transactions
//                    let walletTransactions = try wallet.listTransactions(includeRaw: false)
//                    let actualWalletTransactions = walletTransactions ?? [TransactionDetails]()
//                    self.varWalletTransactions = actualWalletTransactions
//                    print("Updated onchain transactions: \(actualWalletTransactions.count)")
//                    
//                    // Get current height
//                    let fetchedCurrentHeight = try blockchain.getHeight()
//                    self.currentHeight = Int(fetchedCurrentHeight)
//                    
//                    // Send notification that sync is complete
//                    DispatchQueue.main.async {
//                        let notificationDict:[String: Any] = ["action":"complete","type":"sync"]
//                        NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "updatesync"), object: nil, userInfo: notificationDict) as Notification)
//                    }
//                    
//                    // Get updated lightning data and send notification
//                    Task {
//                        do {
//                            let channels = try await self.listChannels()
//                            let payments = try await self.listPayments()
//                            
//                            // Send notification with all updated details
//                            let transactionsNotificationDict:[AnyHashable:Any] = [
//                                "transactions": actualWalletTransactions, 
//                                "channels": channels, 
//                                "payments": payments, 
//                                "bdkbalance": self.bdkBalance, 
//                                "currentheight": self.currentHeight
//                            ]
//                            DispatchQueue.main.async {
//                                NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "getwalletdata"), object: nil, userInfo: transactionsNotificationDict) as Notification)
//                            }
//                        } catch {
//                            print("Error getting lightning data during sync: \(error.localizedDescription)")
//                        }
//                    }
//                } else {
//                    print("Wallet or blockchain not available for sync")
//                }
//            } catch {
//                print("Error during wallet sync: \(error.localizedDescription)")
//                DispatchQueue.main.async {
//                    let notificationDict:[String: Any] = ["action":"complete","type":"sync"]
//                    NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "updatesync"), object: nil, userInfo: notificationDict) as Notification)
//                }
//            }
//        }
//    }
    
    func receivePayment(amountMsat: UInt64, description: String, expirySecs: UInt32) async throws -> Bolt11Invoice {
        let invoiceDescription = Bolt11InvoiceDescription.direct(description: description)
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
            //let invoiceAmountInt = Int(invoiceAmount)
            return invoiceDetails
        } else {
            return nil
        }
    }
    
    func getClient() -> ElectrumClient? {
        return self.electrumClient
    }
    
    func getEsploraClient() -> EsploraClient? {
        var esploraUrl = Constants.Config.EsploraServerURLNetwork.Bitcoin.bitcoin_mempoolspace
        if UserDefaults.standard.value(forKey: "envkey") as? Int == 0 {
            esploraUrl = Constants.Config.EsploraServerURLNetwork.regtest
        }
        return EsploraClient(url: esploraUrl)
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
        self.bdkBalance = 0
        self.varWalletTransactions = []
        self.currentHeight = 0
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
            let network: KeyDerivationNetwork = UserDefaults.standard.value(forKey: "envkey") as? Int == 0 ? .testnet : .mainnet
            
            // Create SimpleKeyDerivation instance with the stored mnemonic
            let keyDerivation = try SimpleKeyDerivation(mnemonic: self.varMnemonicString, network: network)
            
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
