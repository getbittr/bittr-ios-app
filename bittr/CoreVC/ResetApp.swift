//
//  ResetApp.swift
//  bittr
//
//  Created by Tom Melters on 08/02/2024.
//

import UIKit
import LDKNode
import Sentry

extension CoreViewController {
    
    func startPinReset() {
        
        // Set pin reset attempt.
        self.resettingPin = true
        
        // Launch signup for mnemonic check.
        self.launchSignup(onPage: 2)
        
        // Show signup.
        self.showSignup()
    }
    
    func launchSignup(onPage:Int) {
        if self.signupContainerView.subviews.count == 0 {
            // Add signup view to container.
            let storyboard = UIStoryboard(name: "Main", bundle: Bundle.main)
            let newChild = storyboard.instantiateViewController(withIdentifier: "Signup")
            (newChild as! SignupViewController).coreVC = self
            self.addChild(newChild)
            newChild.view.frame.size = self.signupContainerView.frame.size
            self.signupContainerView.addSubview(newChild.view)
            newChild.didMove(toParent: self)
            
            (newChild as! SignupViewController).animateTransition = false
            (newChild as! SignupViewController).moveToPage(onPage)
        }
    }
    
    func restoreWalletTapped() {
        // This function is reached from:
        // - The RestoreVC in case the user has lost their mnemonic and pin (before syncing).
        // - The HomeVC finalizeSync function in case the user has lost their mnemonic and pin (after syncing).
        // - The PinVC in case the user has entered the wrong pin 10 times.
        // - The SettingsVC when the user wants to remove their wallet.
        Log.info("Restore wallet tapped.")
        
        if !self.walletHasSynced {
            if self.resettingPin {
                Log.info("The user wants to remove the wallet from the Reset PIN view.")
                self.showAlert(presentingController: self, title: Language.getWord(withID: "removewalletfromdevice"), message: Language.getWord(withID: "removewallet1"), buttons: [Language.getWord(withID: "cancel"), Language.getWord(withID: "removewalletfromdevice")], actions: [nil, #selector(self.startWalletInBackground)])
            } else if self.removingWalletForIncorrectPin {
                Log.info("Will start wallet in background.")
                self.startWalletInBackground()
            } else {
                Log.info("Wallet is syncing.")
                self.showAlert(presentingController: self, title: Language.getWord(withID: "syncingwallet"), message: Language.getWord(withID: "syncingwallet2"), buttons: [Language.getWord(withID: "okay")], actions: nil)
            }
        } else {
            Log.info("Wallet is ready.")
            if BitcoinManager.shared.listChannels().getActiveChannel() != nil {
                // Check if we've recently initiated channel closure.
                
                // Stop spinner
                self.genericSpinner.stopAnimating()
                self.fullViewCover.alpha = 0
                
                // If channel closure was initiated within the last 2 minutes, allow reset.
                if self.channelWasClosedRecently() {
                    // Allow wallet reset since channel is in closing process.
                    if self.removingWalletForIncorrectPin {
                        self.performWalletReset()
                    } else {
                        self.showAlert(presentingController: self, title: Language.getWord(withID: "restorewallet"), message: Language.getWord(withID: "restorewallet5"), buttons: [Language.getWord(withID: "cancel"), Language.getWord(withID: "restore")], actions: [nil, #selector(self.walletRestoreAlert)])
                    }
                } else {
                    Log.info("Wallet cannot be restored with open channels.")
                    if self.removingWalletForIncorrectPin {
                        self.closeChannelConfirmed()
                    } else {
                        self.showAlert(presentingController: self, title: Language.getWord(withID: "restorewallet"), message: Language.getWord(withID: "restorewallet4"), buttons: [Language.getWord(withID: "cancel"), Language.getWord(withID: "closechannel")], actions: [nil, #selector(self.closeChannelAlert)])
                    }
                }
            } else {
                // Clear channel closing state since no channels exist
                UserDefaults.standard.removeObject(forKey: "channelClosingInitiated")
                UserDefaults.standard.removeObject(forKey: "channelClosingTimestamp")
                
                if self.resettingPin || self.removingWalletForIncorrectPin {
                    Log.info("Removing wallet without signing in.")
                    self.performWalletReset()
                } else {
                    // Retore wallet.
                    self.showAlert(presentingController: self, title: Language.getWord(withID: "restorewallet"), message: Language.getWord(withID: "restorewallet2"), buttons: [Language.getWord(withID: "cancel"), Language.getWord(withID: "restore")], actions: [nil, #selector(self.walletRestoreAlert)])
                }
            }
        }
    }
    
    @objc func startWalletInBackground() {
        self.hideAlert()
        
        // The user wishes to remove the wallet from the device, without signing in.
        Log.info("Start wallet in background.")
        
        // Activate spinner.
        self.fullViewCover.alpha = 0.8
        self.genericSpinner.startAnimating()
        
        // Sync wallet.
        Task {
            await self.startWallet()
        }
    }
    
    @objc func walletRestoreAlert() {
        self.hideAlert()
        self.showAlert(presentingController: self, title: Language.getWord(withID: "restorewallet"), message: Language.getWord(withID: "restorewallet3"), buttons: [Language.getWord(withID: "cancel"), Language.getWord(withID: "restore")], actions: [nil, #selector(self.performWalletReset)])
    }
    
    @objc func closeChannelAlert() {
        self.hideAlert()
        self.showAlert(presentingController: self, title: Language.getWord(withID: "closechannel"), message: Language.getWord(withID: "closechannel2"), buttons: [Language.getWord(withID: "cancel"), Language.getWord(withID: "closechannel")], actions: [nil, #selector(self.closeChannelConfirmed)])
    }
    
    @objc func closeChannelConfirmed() {
        self.hideAlert()
        
        if let closingChannel = BitcoinManager.shared.listChannels().getActiveChannel() {
            do {
                Log.info("Will attempt channel closure.")
                try BitcoinManager.shared.closeChannel(userChannelId: closingChannel.userChannelId, counterPartyNodeId: closingChannel.counterpartyNodeId)
            } catch {
                Log.info("Unsuccessful channel closure.")
                DispatchQueue.main.async {
                    SentrySDK.capture(error: error) { scope in
                        scope.setExtra(value: "ResetApp row 170", key: "context")
                    }
                    if self.removingWalletForIncorrectPin {
                        self.forceCloseChannel()
                    } else {
                        self.showAlert(presentingController: self, title: Language.getWord(withID: "closechannel6"), message: Language.getWord(withID: "closechannel7"), buttons: [Language.getWord(withID: "cancel"), Language.getWord(withID: "forceclose")], actions: [nil, #selector(self.forceCloseChannel)])
                    }
                }
                return
            }
                
            // Mark that we've initiated channel closure
            UserDefaults.standard.set(true, forKey: "channelClosingInitiated")
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "channelClosingTimestamp")
            
            // Successful channel closure.
            DispatchQueue.main.async {
                if self.removingWalletForIncorrectPin {
                    self.performWalletReset()
                } else {
                    self.didCloseChannel()
                    self.showAlert(presentingController: self, title: Language.getWord(withID: "closechannel"), message: Language.getWord(withID: "closechannel5"), buttons: [Language.getWord(withID: "okay")], actions: [#selector(self.performWalletReset)])
                }
            }
        } else {
            // No channels to close, proceed with reset
            DispatchQueue.main.async {
                self.performWalletReset()
            }
        }
    }
    
    @objc func forceCloseChannel() {
        self.hideAlert()
        
        if let closingChannel = BitcoinManager.shared.listChannels().getActiveChannel() {
            // Try force close (unilateral closure)
            Log.info("Attempting force close for channel.")
            print("Channel ID: \(closingChannel.userChannelId)")
            
            do {
                try BitcoinManager.shared.forceCloseChannel(userChannelId: closingChannel.userChannelId, counterPartyNodeId: closingChannel.counterpartyNodeId)
            } catch {
                Log.info("Unsuccessful channel closure.")
                DispatchQueue.main.async {
                    SentrySDK.capture(error: error) { scope in
                        scope.setExtra(value: "ResetApp row 213", key: "context")
                    }
                    if !self.removingWalletForIncorrectPin {
                        self.showAlert(presentingController: self, title: Language.getWord(withID: "closechannel"), message: "Force close also failed. Please try again later or contact support.", buttons: [Language.getWord(withID: "okay")], actions: nil)
                    }
                }
                return
            }
                
            // Mark that we've initiated channel closure
            UserDefaults.standard.set(true, forKey: "channelClosingInitiated")
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "channelClosingTimestamp")
            
            // Successful force close
            DispatchQueue.main.async {
                if self.removingWalletForIncorrectPin {
                    self.performWalletReset()
                } else {
                    self.didCloseChannel()
                    self.showAlert(presentingController: self, title: Language.getWord(withID: "forceclose"), message: "Force close initiated successfully. This may take longer than normal closure due to higher transaction fees.", buttons: [Language.getWord(withID: "okay")], actions: [#selector(self.performWalletReset)])
                }
            }
        } else {
            // No channels to close, proceed with reset
            DispatchQueue.main.async {
                self.performWalletReset()
            }
        }
    }
    
    @objc func performWalletReset() {
        self.hideAlert()
        
        // Reset PIN reset state
        self.resettingPin = false
        self.removingWalletForIncorrectPin = false
        
        // Clear channel closing state
        UserDefaults.standard.removeObject(forKey: "channelClosingInitiated")
        UserDefaults.standard.removeObject(forKey: "channelClosingTimestamp")
        
        // Clear mnemonic from cache
        CacheManager.deleteClientInfo()
        
        // Remove wallet from device and remove corresponding cached data.
        do {
            Log.info("Starting wallet reset cleanup")
            
            // Always try to stop the node first if it exists
            if BitcoinManager.shared.ldkNode != nil {
                Log.info("Stopping Lightning node")
                try BitcoinManager.shared.stop()
                Log.info("Lightning node stopped successfully")
            }
            
            // Always clean up documents directory
            Log.info("Cleaning up documents directory")
            try BitcoinManager.shared.deleteDocuments()
            Log.info("Documents directory cleaned successfully")
            
            // Reset node state to clear all references
            Log.info("Resetting node state")
            BitcoinManager.shared.resetNodeState()
            Log.info("Node state reset completed")
            
        } catch {
            Log.info("Error during cleanup: \(error.localizedDescription)")
            DispatchQueue.main.async {
                SentrySDK.capture(error: error) { scope in
                    scope.setExtra(value: "ResetApp row 269", key: "context")
                }
            }
            
            // Even if everything fails, try to clean up documents
            do {
                Log.info("Attempting final fallback document cleanup")
                try BitcoinManager.shared.deleteDocuments()
                Log.info("Final fallback document cleanup successful")
            } catch {
                Log.info("Final fallback document cleanup failed: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    SentrySDK.capture(error: error) { scope in
                        scope.setExtra(value: "ResetApp row 282", key: "context")
                    }
                }
            }
        }
        
        // Hide signup view and launch create wallet flow
        // Since we've cleared the PIN, we need to manually show the create wallet flow
        self.homeVC!.view.alpha = 0
        self.hideSignup()
        self.userHasSignedIn = false
        
        // Launch signup on create wallet page after a delay to ensure cleanup is complete
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            Log.info("ResetApp - Launching signup after cleanup")
            self.launchSignup(onPage: 3) // Page 3 is create wallet
            self.showSignup()
            
            // Show HomeVC.
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                self.homeVC!.view.alpha = 1
                self.genericSpinner.stopAnimating()
                self.fullViewCover.alpha = 0
            }
        }
    }
    
    func didCloseChannel() {
        Log.info("didCloseChannel() - Clearing channel cache and triggering sync")
        
        self.bittrWallet.lightningChannels = [ChannelDetails]()
        self.bittrWallet.satoshisLightning = 0
        
        if self.homeVC!.balanceLabel.alpha == 1 {
            self.homeVC!.setTotalSats()
        }
        
        // Trigger a fresh sync to get updated channel data
        do {
            Log.info("Syncing wallet to get updated channel count")
            try BitcoinManager.shared.syncWallets()
        } catch {
            Log.info("Error syncing after channel closure: \(error)")
            DispatchQueue.main.async {
                SentrySDK.capture(error: error) { scope in
                    scope.setExtra(value: "ResetApp row 347", key: "context")
                }
            }
            return
        }
            
        // Get fresh channel data
        let updatedChannels = BitcoinManager.shared.listChannels()
        Log.info("Updated channel count: \(updatedChannels.count)")
        
        DispatchQueue.main.async {
            // Update the cached channel data
            self.bittrWallet.lightningChannels = updatedChannels
            
            // Update balance if needed
            if self.homeVC!.balanceLabel.alpha == 1 {
                self.homeVC!.setTotalSats()
            }
            
            Log.info("Channel cache updated successfully")
        }
    }

}

extension UIViewController {
    
    func channelWasClosedRecently() -> Bool {
        let channelClosingInitiated = UserDefaults.standard.bool(forKey: "channelClosingInitiated")
        let channelClosingTimestamp = UserDefaults.standard.double(forKey: "channelClosingTimestamp")
        let timeSinceClosure = Date().timeIntervalSince1970 - channelClosingTimestamp
        
        // If channel closure was initiated within the last 2 minutes, allow reset
        if channelClosingInitiated && timeSinceClosure < 120 { // 2 minutes
            return true
        } else {
            // Clear old channel closing state if it's been too long
            if channelClosingInitiated && timeSinceClosure >= 120 {
                UserDefaults.standard.removeObject(forKey: "channelClosingInitiated")
                UserDefaults.standard.removeObject(forKey: "channelClosingTimestamp")
            }
            return false
        }
    }
    
}
