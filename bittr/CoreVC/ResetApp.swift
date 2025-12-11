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
    
    func resetApp(nodeIsRunning:Bool) {
        
        if nodeIsRunning {
            // Node is already running, check for channels directly
            checkChannelsAndReset()
        } else {
            // Node is not running, we need to start it first to check for channels
            startNodeAndCheckChannels()
        }
    }
    
    func startNodeAndCheckChannels() {
        // Start the Lightning node first
        
        Task {
            let didStartLDK = await withCheckedContinuation { continuation in
                BitcoinManager.shared.startLDK { didStartLDK in
                    continuation.resume(returning: didStartLDK)
                }
            }
            
            if didStartLDK {
                // Wait a moment for the node to fully initialize
                // 2 seconds
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                
                // Now check for channels
                DispatchQueue.main.async {
                    self.checkChannelsAndReset()
                }
            } else {
                // If we can't start the node, proceed with reset anyway
                DispatchQueue.main.async {
                    self.performWalletReset(nodeIsRunning: false)
                }
            }
        }
    }
    
    func checkChannelsAndReset() {
        Task {
            do {
                let channels = try await BitcoinManager.shared.listChannels()
                DispatchQueue.main.async {
                    if channels.count > 0 {
                        // Check if we've recently initiated channel closure
                        let channelClosingInitiated = UserDefaults.standard.bool(forKey: "channelClosingInitiated")
                        let channelClosingTimestamp = UserDefaults.standard.double(forKey: "channelClosingTimestamp")
                        let timeSinceClosure = Date().timeIntervalSince1970 - channelClosingTimestamp
                        
                        // If channel closure was initiated within the last 2 minutes, allow reset
                        if channelClosingInitiated && timeSinceClosure < 120 { // 2 minutes
                            Log.info("🔍 [DEBUG] ResetApp - Channel closure initiated \(Int(timeSinceClosure/60)) minutes ago, allowing wallet reset")
                            // Allow wallet reset since channel is in closing process
                            self.performWalletReset(nodeIsRunning: true)
                        } else {
                            // Clear old channel closing state if it's been too long
                            if channelClosingInitiated && timeSinceClosure >= 120 {
                                UserDefaults.standard.removeObject(forKey: "channelClosingInitiated")
                                UserDefaults.standard.removeObject(forKey: "channelClosingTimestamp")
                            }
                            
                            // Wallet cannot be reset with open channels.
                            self.showAlert(presentingController: self, title: Language.getWord(withID: "restorewallet"), message: Language.getWord(withID: "restorewallet4"), buttons: [Language.getWord(withID: "cancel"), Language.getWord(withID: "closechannel")], actions: [nil, #selector(self.closeChannelAlert)])
                        }
                    } else {
                        // Clear channel closing state since no channels exist
                        UserDefaults.standard.removeObject(forKey: "channelClosingInitiated")
                        UserDefaults.standard.removeObject(forKey: "channelClosingTimestamp")
                        
                        // Proceed with wallet reset
                        self.performWalletReset(nodeIsRunning: true)
                    }
                }
            } catch {
                // If we can't check channels, assume no channels and proceed
                DispatchQueue.main.async {
                    SentrySDK.capture(error: error) { scope in
                        scope.setExtra(value: "ResetApp row 118", key: "context")
                    }
                    self.performWalletReset(nodeIsRunning: true)
                }
            }
        }
    }
    
    @objc func closeChannelAlert() {
        self.hideAlert()
        self.showAlert(presentingController: self, title: Language.getWord(withID: "closechannel"), message: Language.getWord(withID: "closechannel2"), buttons: [Language.getWord(withID: "cancel"), Language.getWord(withID: "closechannel")], actions: [nil, #selector(self.closeChannelConfirmed)])
    }
    
    @objc func closeChannelConfirmed() {
        self.hideAlert()
        Task {
            do {
                let channels = try await BitcoinManager.shared.listChannels()
                var closingChannel:ChannelDetails?
                for eachChannel in channels {
                    if eachChannel.isChannelReady {
                        closingChannel = eachChannel
                    }
                }
                if closingChannel != nil {
                    try BitcoinManager.shared.closeChannel(userChannelId: closingChannel!.userChannelId, counterPartyNodeId: closingChannel!.counterpartyNodeId)
                    
                    // Mark that we've initiated channel closure
                    UserDefaults.standard.set(true, forKey: "channelClosingInitiated")
                    UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "channelClosingTimestamp")
                    
                    // Successful channel closure.
                    DispatchQueue.main.async {
                        self.didCloseChannel()
                        self.showAlert(presentingController: self, title: Language.getWord(withID: "closechannel"), message: Language.getWord(withID: "closechannel5"), buttons: [Language.getWord(withID: "okay")], actions: [#selector(self.channelClosedProceedWithReset)])
                    }
                } else {
                    // No channels to close, proceed with reset
                    DispatchQueue.main.async {
                        self.performWalletReset(nodeIsRunning: true)
                    }
                }
            } catch {
                // Unsuccessful channel closure.
                Log.info("❌ [DEBUG] ResetApp - Channel closure failed with error: \(error)")
                Log.info("❌ [DEBUG] ResetApp - Error type: \(type(of: error))")
                Log.info("❌ [DEBUG] ResetApp - Error description: \(error.localizedDescription)")
                
                // Log additional error details if available
                if let nsError = error as NSError? {
                    Log.info("❌ [DEBUG] ResetApp - NSError domain: \(nsError.domain)")
                    Log.info("❌ [DEBUG] ResetApp - NSError code: \(nsError.code)")
                    Log.info("❌ [DEBUG] ResetApp - NSError userInfo: \(nsError.userInfo)")
                }
                
                DispatchQueue.main.async {
                    SentrySDK.capture(error: error) { scope in
                        scope.setExtra(value: "ResetApp row 170", key: "context")
                    }
                    self.showAlert(presentingController: self, title: Language.getWord(withID: "closechannel6"), message: Language.getWord(withID: "closechannel7"), buttons: [Language.getWord(withID: "cancel"), Language.getWord(withID: "forceclose")], actions: [nil, #selector(self.forceCloseChannel)])
                }
            }
        }
    }
    
    @objc func forceCloseChannel() {
        self.hideAlert()
        Task {
            do {
                let channels = try await BitcoinManager.shared.listChannels()
                var closingChannel:ChannelDetails?
                for eachChannel in channels {
                    if eachChannel.isChannelReady {
                        closingChannel = eachChannel
                    }
                }
                if closingChannel != nil {
                    // Try force close (unilateral closure)
                    Log.info("🔍 [DEBUG] ResetApp - Attempting force close for channel.")
                    print("Channel ID: \(closingChannel!.userChannelId)")
                    try BitcoinManager.shared.forceCloseChannel(userChannelId: closingChannel!.userChannelId, counterPartyNodeId: closingChannel!.counterpartyNodeId)
                    
                    // Mark that we've initiated channel closure
                    UserDefaults.standard.set(true, forKey: "channelClosingInitiated")
                    UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "channelClosingTimestamp")
                    
                    // Successful force close
                    DispatchQueue.main.async {
                        self.didCloseChannel()
                        self.showAlert(presentingController: self, title: Language.getWord(withID: "forceclose"), message: "Force close initiated successfully. This may take longer than normal closure due to higher transaction fees.", buttons: [Language.getWord(withID: "okay")], actions: [#selector(self.channelClosedProceedWithReset)])
                    }
                    
                } else {
                    // No channels to close, proceed with reset
                    DispatchQueue.main.async {
                        self.performWalletReset(nodeIsRunning: true)
                    }
                }
            } catch {
                Log.info("❌ [DEBUG] ResetApp - Force close failed: \(error)")
                Log.info("❌ [DEBUG] ResetApp - Force close error type: \(type(of: error))")
                Log.info("❌ [DEBUG] ResetApp - Force close error description: \(error.localizedDescription)")
                
                DispatchQueue.main.async {
                    SentrySDK.capture(error: error) { scope in
                        scope.setExtra(value: "ResetApp row 213", key: "context")
                    }
                    self.showAlert(presentingController: self, title: Language.getWord(withID: "closechannel"), message: "Force close also failed. Please try again later or contact support.", buttons: [Language.getWord(withID: "okay")], actions: nil)
                }
            }
        }
    }
    
    @objc func channelClosedProceedWithReset() {
        self.hideAlert()
        self.performWalletReset(nodeIsRunning: true)
    }
    
    func performWalletReset(nodeIsRunning: Bool) {
        
        // Reset PIN reset state
        self.resettingPin = false
        
        // Clear channel closing state
        UserDefaults.standard.removeObject(forKey: "channelClosingInitiated")
        UserDefaults.standard.removeObject(forKey: "channelClosingTimestamp")
        
        // Clear mnemonic from cache
        CacheManager.removeMnemonic()
        
        // Remove wallet from device and remove corresponding cached data.
        do {
            Log.info("🔍 [DEBUG] ResetApp - Starting wallet reset cleanup")
            
            // Always try to stop the node first if it exists
            if BitcoinManager.shared.ldkNode != nil {
                Log.info("🔍 [DEBUG] ResetApp - Stopping Lightning node")
                try BitcoinManager.shared.stop()
                Log.info("🔍 [DEBUG] ResetApp - Lightning node stopped successfully")
            }
            
            // Always clean up documents directory
            Log.info("🔍 [DEBUG] ResetApp - Cleaning up documents directory")
            try BitcoinManager.shared.deleteDocuments()
            Log.info("🔍 [DEBUG] ResetApp - Documents directory cleaned successfully")
            
            // Reset node state to clear all references
            Log.info("🔍 [DEBUG] ResetApp - Resetting node state")
            BitcoinManager.shared.resetNodeState()
            Log.info("🔍 [DEBUG] ResetApp - Node state reset completed")
            
            // Clear all cached data
            Log.info("🔍 [DEBUG] ResetApp - Clearing cached data")
            CacheManager.deleteClientInfo()
            Log.info("🔍 [DEBUG] ResetApp - Cached data cleared successfully")
            
        } catch {
            Log.info("❌ [DEBUG] ResetApp - Error during cleanup: \(error.localizedDescription)")
            DispatchQueue.main.async {
                SentrySDK.capture(error: error) { scope in
                    scope.setExtra(value: "ResetApp row 269", key: "context")
                }
            }
            
            // Even if everything fails, try to clean up documents
            do {
                Log.info("🔍 [DEBUG] ResetApp - Attempting final fallback document cleanup")
                try BitcoinManager.shared.deleteDocuments()
                Log.info("🔍 [DEBUG] ResetApp - Final fallback document cleanup successful")
            } catch {
                Log.info("❌ [DEBUG] ResetApp - Final fallback document cleanup failed: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    SentrySDK.capture(error: error) { scope in
                        scope.setExtra(value: "ResetApp row 282", key: "context")
                    }
                }
            }
            
            CacheManager.deleteClientInfo()
        }
        
        // Hide signup view and launch create wallet flow
        // Since we've cleared the PIN, we need to manually show the create wallet flow
        self.homeVC!.view.alpha = 0
        self.hideSignup()
        self.userHasSignedIn = false
        
        // Launch signup on create wallet page after a delay to ensure cleanup is complete
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            Log.info("🔍 [DEBUG] ResetApp - Launching signup after cleanup")
            self.launchSignup(onPage: 3) // Page 3 is create wallet
            self.showSignup()
            
            // Show HomeVC.
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                self.homeVC!.view.alpha = 1
                self.resettingPin = false
                self.genericSpinner.stopAnimating()
                self.fullViewCover.alpha = 0
            }
        }
    }
    
    func didCloseChannel() {
        Log.info("🔍 [DEBUG] ResetApp - didCloseChannel() - Clearing channel cache and triggering sync")
        
        self.bittrWallet.lightningChannels = [ChannelDetails]()
        self.bittrWallet.satoshisLightning = 0
        
        if self.homeVC!.balanceLabel.alpha == 1 {
            self.homeVC!.setTotalSats(updateTableAfterConversion: false)
        }
        
        // Trigger a fresh sync to get updated channel data
        Task {
            do {
                Log.info("🔍 [DEBUG] ResetApp - didCloseChannel() - Syncing wallet to get updated channel count")
                try BitcoinManager.shared.syncWallets()
                
                // Get fresh channel data
                let updatedChannels = try await BitcoinManager.shared.listChannels()
                Log.info("🔍 [DEBUG] ResetApp - didCloseChannel() - Updated channel count: \(updatedChannels.count)")
                
                DispatchQueue.main.async {
                    // Update the cached channel data
                    self.bittrWallet.lightningChannels = updatedChannels
                    
                    // Update balance if needed
                    if self.homeVC!.balanceLabel.alpha == 1 {
                        self.homeVC!.setTotalSats(updateTableAfterConversion: false)
                    }
                    
                    Log.info("🔍 [DEBUG] ResetApp - didCloseChannel() - Channel cache updated successfully")
                }
            } catch {
                Log.info("❌ [DEBUG] ResetApp - didCloseChannel() - Error syncing after channel closure: \(error)")
                DispatchQueue.main.async {
                    SentrySDK.capture(error: error) { scope in
                        scope.setExtra(value: "ResetApp row 347", key: "context")
                    }
                }
            }
        }
    }

}
