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
        
        switch BitcoinManager.shared.claimNodeStart() {
        case .alreadyRunning:
            // Node is already running.
            self.continueStartWallet()
            
        case .startInFlight:
            // Node is already being started.
            Log.info("Node start already in flight — skipping duplicate startWallet.")
            
        case .proceed:
            // Node has not yet been started.
            self.startSync(.ldk)

            // Watchdog: building/starting the node can hang on network and
            // didStartLDK has no timeout of its own, so without a deadline a
            // hang means spinner-forever. Surface the retry alert after 15s
            // (the same deadline the previous async implementation raced
            // against). Both flags are only touched on main, so no races.
            var ldkStartCompleted = false
            var ldkWatchdogFired = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 15) {
                guard !ldkStartCompleted else { return }
                ldkWatchdogFired = true
                Log.info("Starting LDK Node takes too long.")
                self.showAlert(presentingController: self, title: Language.getWord(withID: "oops"), message: Language.getWord(withID: "walletconnectfail"), buttons: [Language.getWord(withID: "tryagain")], actions: [#selector(self.restartLightning)])
            }

            DispatchQueue.global(qos: .userInitiated).async {
                let didStartLDKNode = self.startLightning()
                BitcoinManager.shared.endNodeStart()
                DispatchQueue.main.async {
                    ldkStartCompleted = true
                    // The watchdog already surfaced the retry alert; Try again
                    // re-enters startWallet, which sees the now-running node
                    // and continues immediately.
                    guard !ldkWatchdogFired else { return }
                    guard didStartLDKNode else {
                        self.showAlert(presentingController: self, title: Language.getWord(withID: "oops"), message: Language.getWord(withID: "walletconnectfail"), buttons: [Language.getWord(withID: "tryagain")], actions: [#selector(self.restartLightning)])
                        return
                    }
                    self.continueStartWallet()
                }
            }
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
            
            // Load wallet data — mixed data + UI work (balance labels, table
            // reload, finalizeSync), so it must run on main, same as the hop
            // syncLDKnode keeps for the identical call. Splitting its data
            // phase off-main is the better follow-up. BDK start continues on
            // this queue concurrently, as it did before the refactor.
            DispatchQueue.main.async {
                self.homeVC?.loadWalletData()
            }

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
