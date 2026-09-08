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

        // Both flags are only touched on main, so no races.
        var ldkStartCompleted = false
        var ldkWatchdogFired = false

        let showRetryAlert = { [weak self] in
            guard let self else { return }
            self.showAlert(title: Language.getWord(withID: "oops"), message: Language.getWord(withID: "walletconnectfail"), buttons: [.action(Language.getWord(withID: "tryagain")) { self.startWallet() }])
        }

        // Watchdog: building/starting the node can hang on network and
        // didStartLDK has no timeout of its own, so without a deadline a hang
        // means spinner-forever. Surface the retry alert after 15s (the same
        // deadline the previous async implementation raced against).
        let armWatchdog = {
            DispatchQueue.main.asyncAfter(deadline: .now() + 15) {
                guard !ldkStartCompleted else { return }
                ldkWatchdogFired = true
                Log.info("Starting LDK Node takes too long.")
                showRetryAlert()
            }
        }

        // Called on main with the outcome of the start this call is riding on —
        // whether we own it or attached to one already in flight.
        let finish: (Bool) -> Void = { [weak self] didStartLDKNode in
            ldkStartCompleted = true
            // The watchdog already surfaced the retry alert; Try again re-enters
            // startWallet, which either sees the now-running node or attaches to
            // the start still in flight.
            guard !ldkWatchdogFired else { return }
            guard didStartLDKNode else {
                showRetryAlert()
                return
            }
            self?.continueStartWallet()
        }

        switch BitcoinManager.shared.claimNodeStart(onInFlightStart: finish) {
        case .alreadyRunning:
            // Node is already running.
            self.continueStartWallet()

        case .startInFlight:
            // A start is already running and `finish` is now attached to it, so
            // this call still gets an outcome instead of returning into nothing.
            // Arm a watchdog here too: this branch is exactly where the retry
            // alert's Try again lands when a start hangs, and without a fresh
            // deadline that tap would dismiss the alert with nothing left to
            // re-show it — leaving the user behind a full-screen cover with no
            // action available, on the lockout path especially.
            Log.info("Node start already in flight — attaching to it.")
            self.startSync(.ldk)
            armWatchdog()

        case .proceed:
            // Node has not yet been started.
            self.startSync(.ldk)
            armWatchdog()

            DispatchQueue.global(qos: .userInitiated).async {
                let didStartLDKNode = BitcoinManager.shared.runClaimedNodeStart {
                    self.startLightning()
                }
                DispatchQueue.main.async {
                    finish(didStartLDKNode)
                }
            }
        }
    }
    
    func continueStartWallet() {

        // One node start can have several startWallet callers riding on it, and
        // each of them is told when it finishes. The work below (syncWallets,
        // loadWalletData, startBDK) is global rather than per-caller, so let the
        // first one through and drop the rest until it has finished. Only ever
        // touched on main.
        guard !self.isContinuingStartWallet else {
            Log.info("continueStartWallet already running — skipping duplicate.")
            return
        }
        self.isContinuingStartWallet = true

        self.completeSync(.ldk)
        
        if BitcoinManager.shared.didQuarantineForeignState {
            Log.info("User has restored a backup on a new device. Their channel will not be available.")
            // This is only reachable for users with Lightning connections before these stopped being synced.
            // Newer users will never encounter this issue.
            BitcoinManager.shared.didQuarantineForeignState = false
            self.showAlert(title: Language.getWord(withID: "restoredbackup"), message: Language.getWord(withID: "restoredbackup2"), buttons: [.dismiss(Language.getWord(withID: "okay"))])
        }
        
        // Start final calculations.
        self.startSync(.final)
        
        // Set CoreVC.
        BitcoinManager.shared.coreVC = self
        
        if !isConnectedToPeer() {
            // Connect to peer.
            Task { _ = await BitcoinManager.shared.connectToLightningPeer()}
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            // Release the guard however this block exits, so a later restart
            // (after a reset, or a genuinely new start) isn't locked out by it.
            defer { DispatchQueue.main.async { self.isContinuingStartWallet = false } }

            guard BitcoinManager.shared.ldkNode != nil else { return }

            // Sync wallet.
            do {
                try BitcoinManager.shared.syncWallets()
            } catch {
                Log.info("startWallet syncWallets failed: \(error.localizedDescription)")
                SentryManager.capture(error, context: "StartLightning syncWallets")
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
                // A timed-out scan blocks Send and Swap for the rest of the
                // session. On this path nobody else is listening — the user is
                // on the home screen — so say so rather than failing silently.
                if BitcoinManager.shared.bdkFullScanTimedOut {
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
