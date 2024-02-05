//
//  LightningNodeService.swift
//  bittr
//
//  Created by Tom Melters on 18/07/2023.
//

import Foundation
import LDKNode
import BitcoinDevKit
import KeychainSwift
import bdkFFI
import LightningDevKit

class LightningNodeService {
    private let ldkNode: LdkNode
    private let keychain = KeychainSwift()
    private let mnemonicKey = ""
    private let storageManager = LightningStorage()
    private var bdkWallet: BitcoinDevKit.Wallet?
    private var blockchain: Blockchain?
    private var xpub = ""
    private var bdkBalance = 0
    private var varWalletTransactions = [TransactionDetails]()
    
    class var shared: LightningNodeService {
        struct Singleton {
            static let instance = LightningNodeService(network: .testnet)
        }
        return Singleton.instance
    }
    
    
    init(network: LDKNode.Network) {
        
        // Step 5.
        
        try? FileManager.deleteLDKNodeLogLatestFile()
        
        let config = Config(
            storageDirPath: storageManager.getDocumentsDirectory(),
            network: network,
            listeningAddress: "0.0.0.0:9735",
            defaultCltvExpiryDelta: UInt32(144),
            onchainWalletSyncIntervalSecs: UInt64(60),
            walletSyncIntervalSecs: UInt64(20),
            feeRateCacheUpdateIntervalSecs: UInt64(600),
            logLevel: .debug
//            ,trustedPeers0conf: ["026d74bf2a035b8a14ea7c59f6a0698d019720e812421ec02762fdbf064c3bc326"]
        )
        
        let nodeBuilder = Builder.fromConfig(config: config)
        
        // For now, the mnemonic can only be set once before the first-ever startup of the ldkNode. It cannot be changed later on.
        var mnemonicString = ""
        keychain.synchronizable = true
        if CacheManager.getMnemonic() != "empty" {
            mnemonicString = CacheManager.getMnemonic()
            print("Cached mnemonicString: \(mnemonicString)")
            /*keychain.set(mnemonicString, forKey: mnemonicKey)
            print("Keychain: \(keychain.get(mnemonicKey) ?? "None")")*/
            keychain.delete(mnemonicKey)
        } else {
            if let storedMnemonic = keychain.get(mnemonicKey) {
                // Migration away from Keychain.
                mnemonicString = storedMnemonic
                print("mnemonicString: \(mnemonicString)")
                CacheManager.storeMnemonic(mnemonic: mnemonicString)
                keychain.delete(mnemonicKey)
            } else {
                let mnemonic = BitcoinDevKit.Mnemonic.init(wordCount: .words12)
                mnemonicString = mnemonic.asString() //"mutual welcome bird hawk mystery warfare dinosaur sure tray coyote video cool"
                print("New mnemonicString: \(mnemonicString)")
                //keychain.set(mnemonicString, forKey: mnemonicKey)
                CacheManager.storeMnemonic(mnemonic: mnemonicString)
            }
        }
        
        // Step 6.
        let notificationDict:[String: Any] = ["mnemonic":mnemonicString]
        NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "setwords"), object: nil, userInfo: notificationDict) as Notification)
        
        nodeBuilder.setEntropyBip39Mnemonic(mnemonic: mnemonicString, passphrase: "")
        
        var wallet_transactions:[TransactionDetails]?
        
        // BDK launch.
        do {
            
            // Attempt to create a mnemonic object from the provided mnemonic string.
            let mnemonic = try BitcoinDevKit.Mnemonic.fromString(mnemonic: mnemonicString)
            
            // Create a BIP32 extended root key using the mnemonic and a nil password
            let bip32ExtendedRootKey = DescriptorSecretKey(network: .testnet, mnemonic: mnemonic, password: nil)
            
            // Create a BIP84 external descriptor using the BIP32 extended root key, specifying the keychain as external and the network as testnet
            let bip84ExternalDescriptor = Descriptor.newBip84(secretKey: bip32ExtendedRootKey, keychain: .external, network: .testnet)
            
            let descriptor = bip84ExternalDescriptor.asString()
            
            let components = descriptor.components(separatedBy: "]")
            
            if components.count > 1 {
                
                let xpubPart = components[1].split(separator: "/").first
                
                if let xpub = xpubPart {
                    print("XPUB: \(xpub)")
                    self.xpub = String(xpub)
                } else {
                    print("Error: Could not extract XPUB")
                }
                
            } else {
                print("Error: Descriptor format not recognized")
            }
            
            // Create a BIP84 internal descriptor using the same BIP32 extended root key, specifying the keychain as internal and the network as testnet
            let bip84InternalDescriptor = Descriptor.newBip84(secretKey: bip32ExtendedRootKey, keychain: .internal, network: .testnet)
            
            // Set up the local SQLite database for the Bitcoin wallet using the provided file path
            let dbPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!.appendingPathComponent("bitcoin_wallet.sqlite")
            let config = SqliteDbConfiguration(path: dbPath.path)
            
            // Initialize a wallet instance using the BIP84 external and internal descriptors, testnet network, and SQLite database configuration
            let wallet = try BitcoinDevKit.Wallet.init(descriptor: bip84ExternalDescriptor, changeDescriptor: bip84InternalDescriptor, network: .testnet, databaseConfig: .sqlite(config: config))
            
            // Configure and create an Electrum blockchain connection to interact with the Bitcoin network
            let electrum = ElectrumConfig(url: "ssl://electrum.blockstream.info:60002", socks5: nil, retry: 5, timeout: nil, stopGap: 10, validateDomain: true)
            let blockchainConfig = BlockchainConfig.electrum(config: electrum)
            let blockchain = try Blockchain(config: blockchainConfig)
            self.blockchain = blockchain
            
            // Synchronize the wallet with the blockchain, ensuring transaction data is up to date
            try wallet.sync(blockchain: blockchain, progress: nil)
            self.bdkWallet = wallet
            
            // Uncomment the following lines to get the on-chain balance (although LDK also does that
            // Get the confirmed balance from the wallet
            bdkBalance = Int(try wallet.getBalance().confirmed)
            // print("transactions: \(balance)")
            
            // Retrieve a list of transaction details from the wallet, excluding raw transaction data
            wallet_transactions = try wallet.listTransactions(includeRaw: false)
            
            // Print the balance and the list of wallet transactions
            print("wallet_transactions fetched.")
            
            // Uncomment the following lines to get a new address from the wallet
            // let new_address = try wallet.getAddress(addressIndex: AddressIndex.new)
            // print("new_address: \(new_address.address.asString())")
            
        } catch {
            print("Some error occurred. \(error.localizedDescription)")
        }
        
        let actualWalletTransactions = wallet_transactions ?? [TransactionDetails]()
        self.varWalletTransactions = actualWalletTransactions
        
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
        
        let ldkNode = try! nodeBuilder.build()
        
        self.ldkNode = ldkNode
        
    }
    
    
    func connectToLightningPeer() {
        
        // Connect to Lightning peer.
        let nodeId = "026d74bf2a035b8a14ea7c59f6a0698d019720e812421ec02762fdbf064c3bc326" // Extract this from your peer string
        let address = "109.205.181.232:9735" // Extract this from your peer string
        
        Task {
            do {
                try await LightningNodeService.shared.connect(
                    nodeId: nodeId,
                    address: address,
                    persist: true
                )
                print("Did connect to peer.")
                self.getChannelsAndPayments(actualWalletTransactions: self.varWalletTransactions)
            } catch let error as NodeError {
                let errorString = handleNodeError(error)
                DispatchQueue.main.async {
                    // Handle UI error showing here, like showing an alert
                    print("Can't connect to peer: \(errorString)")
                    self.getChannelsAndPayments(actualWalletTransactions: self.varWalletTransactions)
                }
            } catch {
                DispatchQueue.main.async {
                    // Handle UI error showing here, like showing an alert
                    print("Can't connect to peer: No error message.")
                    self.getChannelsAndPayments(actualWalletTransactions: self.varWalletTransactions)
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
                
                let payments = try await LightningNodeService.shared.listPayments()
                print("Payments: \(payments.count)")
                
                var transactionsNotificationDict = [AnyHashable:Any]()
                transactionsNotificationDict = ["transactions":actualWalletTransactions,"lightningnodeservice":self,"channels":channels, "payments":payments, "bdkbalance":bdkBalance]
                
                // Step 9.
                NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "getwalletdata"), object: nil, userInfo: transactionsNotificationDict) as Notification)
            } catch {
                print("Error listing channels: \(error.localizedDescription)")
            }
        }
    }
    
    
    func sendToOnchainAddress(address: LDKNode.Address, amountMsat: UInt64) throws -> Txid {
        let txId = try ldkNode.sendToOnchainAddress(address: address, amountMsat: amountMsat)
        return txId
    }
    
    
    func start() async throws {
        
        // Step 4.
        try ldkNode.start()
    }
    
    
    func stop() throws {
        try ldkNode.stop()
    }
    
    func nodeId() -> String {
        let nodeID = ldkNode.nodeId()
        return nodeID
    }
    
    func newFundingAddress() async throws -> String {
        let fundingAddress = try ldkNode.newOnchainAddress()
        return fundingAddress
    }
    
    func getTotalOnchainBalanceSats() async throws -> UInt64 {
        let balance = try ldkNode.totalOnchainBalanceSats()
        return balance
    }
    
    func signMessage(message: String) async throws -> String {
        guard let data = message.data(using: .utf8) else {
            throw NSError(domain: "InvalidInput", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid input string. Couldn't convert to UTF8 data."])
        }
        
        let bytes = [UInt8](data)
        let signedMessage = try ldkNode.signMessage(msg: bytes)
        
        return signedMessage
    }
    
    func listPeers() async throws -> [PeerDetails] {
        let peers = ldkNode.listPeers()
        return peers
    }
    
    func listPayments() async throws -> [PaymentDetails] {
        let payments = ldkNode.listPayments()
        return payments
    }
    
    func listChannels() async throws -> [LDKNode.ChannelDetails] {
        let channels = ldkNode.listChannels()
        return channels
    }
    
    func connect(nodeId: PublicKey, address: String, persist: Bool) async throws {
        try ldkNode.connect(
            nodeId: nodeId,
            address: address,
            persist: persist
        )
    }
    
    func syncWallets() throws {
        try ldkNode.syncWallets()
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
            } catch {
                print("Error getting transactions. \(error.localizedDescription)")
            }
        }
    }
    
    func receivePayment(amountMsat: UInt64, description: String, expirySecs: UInt32) async throws -> Invoice {
        let invoice = try ldkNode.receivePayment(amountMsat: amountMsat, description: description, expirySecs: expirySecs)
        return invoice
    }
    
    func sendPayment(invoice: Invoice) async throws -> PaymentHash {
        let paymentHash = try ldkNode.sendPayment(invoice: invoice)
        return paymentHash
    }
    
    func getInvoiceHash(invoiceString:String) -> String {
        
        let result = Bolt11Invoice.fromStr(s: invoiceString)
        if result.isOk() {
            if let invoice = result.getValue() {
                print("Invoice parsed successfully: \(invoice)")
                let paymentHash:[UInt8] = invoice.paymentHash()!
                let hexString = paymentHash.map { String(format: "%02x", $0) }.joined()
                return hexString
            } else {
                return "empty"
            }
        } else if let error = result.getError() {
            print("Failed to parse invoice: \(error)")
            return "empty"
        } else {
            return "empty"
        }
    }



}

