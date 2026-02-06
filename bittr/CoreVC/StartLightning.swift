//
//  StartLightning.swift
//  bittr
//
//  Created by Tom Melters on 08/02/2024.
//

import UIKit
import LDKNode
import Sentry

extension CoreViewController {
    
    func startWallet() async {
        
        // Sync LDKNode.
        if BitcoinManager.shared.ldkNode == nil || BitcoinManager.shared.status()?.isRunning == false {
            self.startSync(.ldk)
            let didStartLDKNode = await self.startLightning()
            guard didStartLDKNode else { return }
        }
        self.completeSync(.ldk)
        
        // Start final calculations.
        self.startSync(.final)
        
        // Set CoreVC.
        if BitcoinManager.shared.coreVC == nil {
            BitcoinManager.shared.coreVC = self
        }
        
        // Cache Bittr address.
        // Upon first-ever wallet launch, store first onchain address as Bittr address.
        if CacheManager.getBittrAddress() == nil, let onchainAddress = CacheManager.getLastAddress() ?? BitcoinManager.shared.getNewOnchainAddress() {
            
            CacheManager.storeBittrAddress(onchainAddress)
            Log.info("Did store Bittr address.")
        }
        
        // Get latest block height.
        let _ = await BitcoinManager.shared.didGetLatestBlockHeight()
        
        // Check peer connection.
        if !self.isConnectedToPeer() {
            // Connect to peer.
            _ = await BitcoinManager.shared.connectToLightningPeer()
        }
        
        // Get channels and payments.
        // Load wallet data.
        DispatchQueue.main.async {
            self.homeVC?.loadWalletData()
        }
        
        // Start BDK.
        BitcoinManager.shared.didStartBDK { success in
            if success {
                Log.info("Did start BDK.")
                BitcoinManager.shared.didSyncBdkWallet { hasBeenSynced in
                    if hasBeenSynced {
                        Log.info("Did scan BDK wallet.")
                        // Start timer
                        if self.walletSync == nil {
                            self.walletSync = BackgroundSync()
                            self.walletSync!.start()
                        }
                        // Check if VCs are awaiting BDK scan.
                        DispatchQueue.main.async {
                            self.homeVC?.sendVC?.setSendAllLabel()
                            self.homeVC?.moveVC?.swapVC?.calculateSendableAmount()
                        }
                    } else {
                        Log.info("Could not scan BDK wallet.")
                    }
                }
            } else {
                Log.info("Could not start BDK.")
            }
        }
    }

    func startLightning() async -> Bool {
        
        var didStartNode = await withTaskGroup(of: Bool.self) { group -> Bool in
            
            // Start LDK node.
            group.addTask {
                return await withCheckedContinuation { continuation in
                    BitcoinManager.shared.startLDK { didStartLDK in
                        continuation.resume(returning: didStartLDK)
                    }
                }
            }
            
            // 15 second timer.
            group.addTask {
                do {
                    try await Task.sleep(nanoseconds: UInt64(15) * NSEC_PER_SEC)
                } catch {
                    return false
                }
                Log.info("Starting LDK Node takes too long.")
                return false
            }
            
            // Check connection success.
            let firstResult = await group.next() ?? false
            group.cancelAll()
            return firstResult
        }
        
        // Check correct didStartNode boolean.
        if !didStartNode, BitcoinManager.shared.status()?.isRunning == true {
            didStartNode = true
        }
        
        // Proceed to next step.
        if didStartNode {
            Log.info("Did start node.")
            DispatchQueue.main.async {
                SentrySDK.metrics.count(key: "sync.ldk.success")
            }
            return true
        } else {
            Log.info("Could not start node.")
            DispatchQueue.main.async {
                SentrySDK.metrics.count(key: "sync.ldk.failure")
                self.stopLightning(message: nil)
            }
            return false
        }
    }
    
    @objc func restartLightning() {
        
        self.hideAlert()
        Task {
            await self.startWallet()
        }
    }
    
    func stopLightning(message:String?) {
        
        if message != nil {
            self.showAlert(presentingController: self, title: Language.getWord(withID: "oops"), message: "\(Language.getWord(withID: "walletconnectfail")) Error: \(message!)", buttons: [Language.getWord(withID: "tryagain")], actions: [#selector(self.restartLightning)])
        } else {
            self.showAlert(presentingController: self, title: Language.getWord(withID: "oops"), message: Language.getWord(withID: "walletconnectfail"), buttons: [Language.getWord(withID: "tryagain")], actions: [#selector(self.restartLightning)])
        }
    }

}
