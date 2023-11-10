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

class LightningNodeService {
    private let ldkNode: LdkNode
    private let keychain = KeychainSwift()
    private let mnemonicKey = ""
    private let storageManager = LightningStorage()
    
    //private let setWallet:Wallet?
    
    class var shared: LightningNodeService {
        struct Singleton {
            static let instance = LightningNodeService(network: .testnet)
        }
        return Singleton.instance
    }
    
    
    init(network: LDKNode.Network) {
        
        /*if let deleteStorage = UserDefaults.standard.value(forKey: "deletestorage") as? Bool {
            if deleteStorage == true {
                do {
                    try FileManager.default.removeItem(atPath: storageManager.getDocumentsDirectory())
                } catch {
                    print(error.localizedDescription)
                }
                
                UserDefaults.standard.set(false, forKey: "deletestorage")
            }
        }*/
        
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
        let mnemonicString: String
        keychain.synchronizable = true
        if let storedMnemonic = keychain.get(mnemonicKey) {
            mnemonicString = storedMnemonic
            print("mnemonicString: \(mnemonicString)")
        } else {
            let mnemonic = BitcoinDevKit.Mnemonic.init(wordCount: .words12)
            mnemonicString = mnemonic.asString() //"mutual welcome bird hawk mystery warfare dinosaur sure tray coyote video cool"
            print("New mnemonicString: \(mnemonicString)")
            keychain.set(mnemonicString, forKey: mnemonicKey)
        }
        
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
            
            // Synchronize the wallet with the blockchain, ensuring transaction data is up to date
            try wallet.sync(blockchain: blockchain, progress: nil)
            
            // Uncomment the following lines to get the on-chain balance (although LDK also does that
            // Get the confirmed balance from the wallet
            // let balance = try wallet.getBalance().confirmed
            // print("transactions: \(balance)")
            
            // Retrieve a list of transaction details from the wallet, excluding raw transaction data
            wallet_transactions = try wallet.listTransactions(includeRaw: false)
            
            // Print the balance and the list of wallet transactions
            print("wallet_transactions: \(wallet_transactions ?? [TransactionDetails]())")
            
            // Uncomment the following lines to get a new address from the wallet
            // let new_address = try wallet.getAddress(addressIndex: AddressIndex.new)
            // print("new_address: \(new_address.address.asString())")
            
        } catch {
            print("Some error occurred. \(error.localizedDescription)")
        }
        
        
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
        
        
        
        //let listedChannels = self.ldkNode.listChannels()
        
        /*do {
            try syncWallets()*/
            
            //let listedChannels = self.listChannels()
            //let listedPayments = self.listPayments()
            //let listedPeers = self.listPeers()
        /*} catch {
            print("Some error occurred 159. \(error.localizedDescription)")
        }*/
        
        var transactionsNotificationDict = [AnyHashable:Any]()
        if let actualTransactions = wallet_transactions {
            transactionsNotificationDict = ["transactions":actualTransactions,"lightningnodeservice":self]
        }
        
        NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "getwalletdata"), object: nil, userInfo: transactionsNotificationDict) as Notification)
    }
    
    
    func sendToOnchainAddress(address: LDKNode.Address, amountMsat: UInt64) throws -> Txid {
        let txId = try ldkNode.sendToOnchainAddress(address: address, amountMsat: amountMsat)
        return txId
    }
    
    
    func start() async throws {
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
    
    func listPeers() -> [PeerDetails] {
        let peers = ldkNode.listPeers()
        return peers
    }
    
    func listPayments() -> [PaymentDetails] {
        let payments = ldkNode.listPayments()
        return payments
    }
    
    func listChannels() -> [ChannelDetails] {
        let channels = ldkNode.listChannels()
        return channels
    }
    
    func syncWallets() throws {
        try ldkNode.syncWallets()
    }
    
}

