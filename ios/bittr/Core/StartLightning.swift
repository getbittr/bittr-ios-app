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
        
        // Check peer connection.
        if !isConnectedToPeer() {
            // Connect to peer.
            _ = await BitcoinManager.shared.connectToLightningPeer()
        }

        // Ensure LDK has chain-synced before we read balances below.
        // ldkNode.start() returns as soon as the node is up, NOT when it
        // has caught up to the tip — so loadWalletData's call to
        // listBalances().totalOnchainBalanceSats returns 0 for restored
        // wallets that actually have onchain UTXOs, until the 30-sec
        // BackgroundSync.lightSync timer fires (or the user pulls to
        // refresh and re-enters this function). syncWallets is a blocking
        // throwing call, so hop to a background queue and await it.
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                guard BitcoinManager.shared.ldkNode != nil else {
                    continuation.resume()
                    return
                }
                do {
                    try BitcoinManager.shared.syncWallets()
                } catch {
                    Log.info("startWallet syncWallets failed: \(error.localizedDescription)")
                    DispatchQueue.main.async {
                        SentrySDK.capture(error: error) { scope in
                            scope.setExtra(value: "StartLightning syncWallets", key: "context")
                        }
                    }
                }
                continuation.resume()
            }
        }

        // Get channels and payments.
        // Load wallet data.
        DispatchQueue.main.async {
            self.homeVC?.loadWalletData()
        }
        
        // Start BDK if it's not already scanning.
        if !BitcoinManager.shared.bdkWalletIsScanning {
            BitcoinManager.shared.didStartBDK { success in
                if success {
                    Log.info("Did start BDK.")
                    
                    // Manage onchain addresses.
                    if BitcoinManager.shared.bittrWallet.onchainAddresses == nil {
                        DispatchQueue.global(qos: .background).async() {
                            self.manageOnchainAddresses()
                        }
                    }
                    
                    if !BitcoinManager.shared.bdkWalletHasBeenScanned {
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
                        Log.info("Restart BDK light sync timer.")
                        // Start timer
                        if self.walletSync == nil {
                            self.walletSync = BackgroundSync()
                            self.walletSync!.start()
                        }
                    }
                } else {
                    Log.info("Could not start BDK.")
                }
            }
        } else {
            Log.info("Awaiting BDK full scan.")
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
                self.showAlert(presentingController: self, title: Language.getWord(withID: "oops"), message: Language.getWord(withID: "walletconnectfail"), buttons: [Language.getWord(withID: "tryagain")], actions: [#selector(self.restartLightning)])
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

}
