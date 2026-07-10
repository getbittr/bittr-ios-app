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
    
    func startWallet() {
        
        if BitcoinManager.shared.ldkNode == nil || BitcoinManager.shared.status()?.isRunning == false {
            self.startSync(.ldk)
            DispatchQueue.global(qos: .userInitiated).async {
                let didStartLDKNode = self.startLightning()
                DispatchQueue.main.async {
                    guard didStartLDKNode else {
                        self.showAlert(presentingController: self, title: Language.getWord(withID: "oops"), message: Language.getWord(withID: "walletconnectfail"), buttons: [Language.getWord(withID: "tryagain")], actions: [#selector(self.restartLightning)])
                        return
                    }
                    self.continueStartWallet()
                }
            }
        } else {
            self.continueStartWallet()
        }
    }
    
    func continueStartWallet() {
        self.completeSync(.ldk)
        
        // Start final calculations.
        self.startSync(.final)
        
        // Set CoreVC.
        BitcoinManager.shared.coreVC = self
        
        if !isConnectedToPeer() {
            // Connect to peer.
            Task { _ = await BitcoinManager.shared.connectToLightningPeer()}
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            guard BitcoinManager.shared.ldkNode != nil else { return }
            
            // Sync wallet.
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
            
            // Load wallet data.
            self.homeVC?.loadWalletData()
            
            // Start BDK.
            self.startBDK()
        }
    }

    // Runs off the main thread: didStartLDK() is a blocking node build + start.
    // The failure alert is shown by the caller back on main.
    func startLightning() -> Bool {

        // Start LDK Node.
        var didStartNode = BitcoinManager.shared.didStartLDK()

        // Check correct didStartNode boolean.
        if !didStartNode, BitcoinManager.shared.status()?.isRunning == true {
            didStartNode = true
        }

        Log.info("Did start Node: \(didStartNode)")
        SentrySDK.metrics.count(key: didStartNode ? "sync.ldk.success" : "sync.ldk.failure")
        return didStartNode
    }
    
    func startBDK() {
        // Start BDK if it's not already scanning.
        guard !BitcoinManager.shared.bdkWalletIsScanning else {
            Log.info("Awaiting BDK full scan.")
            return
        }
        
        let didStartBDK = BitcoinManager.shared.didStartBDK()
        guard didStartBDK else {
            Log.info("Could not start BDK.")
            return
        }
        Log.info("Did start BDK.")
        
        // Manage onchain addresses.
        if BitcoinManager.shared.bittrWallet.onchainAddresses == nil {
            DispatchQueue.global(qos: .background).async() {
                self.manageOnchainAddresses()
            }
        }
        
        guard !BitcoinManager.shared.bdkWalletHasBeenScanned else {
            Log.info("Restart BDK light sync timer.")
            if self.walletSync == nil {
                self.walletSync = BackgroundSync()
                self.walletSync!.start()
            }
            return
        }
        
        BitcoinManager.shared.didSyncBdkWallet { hasBeenSynced in
            guard hasBeenSynced else {
                Log.info("Could not scan BDK wallet.")
                return
            }
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
        }
    }
    
    @objc func restartLightning() {
        
        self.hideAlert()
        self.startWallet()
    }

}
