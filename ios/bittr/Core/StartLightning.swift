//
//  StartLightning.swift
//  bittr
//
//  Created by Tom Melters on 08/02/2024.
//

import UIKit
import LDKNode

extension CoreViewController {
    
    func startWallet() {
        
        var ldkStartCompleted = false
        var ldkWatchdogFired = false
        
        // Retry alert in case node start takes too long.
        let showRetryAlert = { [weak self] in
            guard let self else { return }
            self.showAlert(title: Language.getWord(withID: "oops"), message: Language.getWord(withID: "walletconnectfail"), buttons: [.action(Language.getWord(withID: "tryagain")) { self.startWallet() }])
        }
        
        // Show the retry alert after 15s.
        let armWatchdog = {
            DispatchQueue.main.asyncAfter(deadline: .now() + 15) {
                guard !ldkStartCompleted else { return }
                ldkWatchdogFired = true
                Log.info("Starting LDK Node takes too long.")
                showRetryAlert()
            }
        }
        
        // How to proceed after starting the node.
        let finish: (Bool) -> Void = { [weak self] didStartLDKNode in
            ldkStartCompleted = true
            guard !ldkWatchdogFired else {
                // Node start was too slow. User has been asked to retry.
                return
            }
            guard didStartLDKNode else {
                // Node start was unsuccessful. Retry.
                showRetryAlert()
                return
            }
            // Node start has been successful. Proceed to next step.
            self?.continueStartWallet()
        }
        
        // Check the current node state.
        switch BitcoinManager.shared.claimNodeStart(onInFlightStart: finish) {
        
        case .alreadyRunning:
            // Node is already running. Proceed to next step.
            self.continueStartWallet()
            
        case .startInFlight:
            // Node start already in flight. Restart timer.
            self.startSync(.ldk)
            armWatchdog()
            
        case .proceed:
            // Node has not yet been started.
            self.startSync(.ldk)
            armWatchdog()
            
            DispatchQueue.global(qos: .userInitiated).async {
                // Start node.
                let didStartLDKNode = BitcoinManager.shared.runClaimedNodeStart {
                    self.startLightning()
                }
                // Proceed to next step.
                DispatchQueue.main.async {
                    finish(didStartLDKNode)
                }
            }
        }
    }
    
    func continueStartWallet() {
        guard !self.isContinuingStartWallet else {
            Log.info("continueStartWallet already running — skipping duplicate.")
            return
        }
        self.isContinuingStartWallet = true
        
        // Node was successfully started.
        self.completeSync(.ldk)
        self.startSync(.wallet)
        
        if BitcoinManager.shared.didQuarantineForeignState {
            Log.info("User has restored a backup on a new device. Their channel will not be available.")
            // This is only reachable for users with Lightning connections before these stopped being synced.
            // Newer users will never encounter this issue.
            BitcoinManager.shared.didQuarantineForeignState = false
            self.showAlert(title: Language.getWord(withID: "restoredbackup"), message: Language.getWord(withID: "restoredbackup2"), buttons: [.dismiss(Language.getWord(withID: "okay"))])
        }
        
        // Set CoreVC.
        BitcoinManager.shared.coreVC = self
        
        if !isConnectedToPeer() {
            // Connect to peer.
            Task { _ = await BitcoinManager.shared.connectToLightningPeer()}
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            defer { DispatchQueue.main.async { self.isContinuingStartWallet = false } }
            guard BitcoinManager.shared.ldkNode != nil else { return }
            
            // Sync wallet.
            var didSyncWallet = true
            do {
                try BitcoinManager.shared.syncWallets()
            } catch {
                Log.info("startWallet syncWallets failed: \(error.localizedDescription)")
                SentryManager.capture(error, context: "StartLightning syncWallets")
                didSyncWallet = false
            }
            if didSyncWallet {
                self.completeSync(.wallet)
            } else {
                self.failSync(.wallet)
            }
            self.startSync(.final)
            
            // Load wallet data.
            DispatchQueue.main.async {
                self.homeVC?.couldNotSyncWallet = !didSyncWallet
                self.homeVC?.loadWalletData()
            }
            
            // Start BDK.
            self.startBDK()
        }
    }
    
    func startLightning() -> Bool {
        
        // Start LDK Node.
        var didStartNode = BitcoinManager.shared.didStartLDK()
        
        // Check correct didStartNode boolean.
        if !didStartNode, BitcoinManager.shared.status()?.isRunning == true {
            didStartNode = true
        }
        
        Log.info("Did start Node: \(didStartNode)")
        SentryManager.countMetric(didStartNode ? "sync.ldk.success" : "sync.ldk.failure")
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
                if BitcoinManager.shared.bdkFullScanTimedOut, self.userHasSignedIn, self.currentPage == .home {
                    self.showAlert(title: Language.getWord(withID: "onchainsyncfailedtitle"), message: Language.getWord(withID: "onchainsynctimedout"), buttons: [.dismiss(Language.getWord(withID: "okay"))])
                }
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
    
}
