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

class LightningNodeService {
    private let ldkNode: LdkNode
    private let keychain = KeychainSwift()
    private let mnemonicKey = ""
    private let storageManager = LightningStorage()
    
    
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
        
        NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "getwalletdata"), object: nil, userInfo: nil) as Notification)
    }
    
    
    
    func start() async throws {
        try ldkNode.start()
    }
    
    
    func stop() throws {
        try ldkNode.stop()
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
    
    func listPayments() -> [PaymentDetails] {
        let payments = ldkNode.listPayments()
        return payments
    }
    
}

