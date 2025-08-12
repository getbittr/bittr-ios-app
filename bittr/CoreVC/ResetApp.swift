//
//  ResetApp.swift
//  bittr
//
//  Created by Tom Melters on 08/02/2024.
//

import UIKit
import LDKNode
import LDKNodeFFI

extension CoreViewController {
    
    func startPinReset() {
        
        // Set pin reset attempt.
        self.resettingPin = true
        
        // Launch signup for mnemonic check.
        self.launchSignup(onPage: 2)
        
        // Show signup.
        self.showSignupView()
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
            do {
                try await LightningNodeService.shared.start()
                
                // Wait a moment for the node to fully initialize
                try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
                
                // Now check for channels
                DispatchQueue.main.async {
                    self.checkChannelsAndReset()
                }
            } catch {
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
                let channels = try await LightningNodeService.shared.listChannels()
                DispatchQueue.main.async {
                    if channels.count > 0 {
                        // Check if we've recently initiated channel closure
                        let channelClosingInitiated = UserDefaults.standard.bool(forKey: "channelClosingInitiated")
                        let channelClosingTimestamp = UserDefaults.standard.double(forKey: "channelClosingTimestamp")
                        let timeSinceClosure = Date().timeIntervalSince1970 - channelClosingTimestamp
                        
                        // If channel closure was initiated within the last 2 minutes, allow reset
                        if channelClosingInitiated && timeSinceClosure < 120 { // 2 minutes
                            print("🔍 [DEBUG] ResetApp - Channel closure initiated \(Int(timeSinceClosure/60)) minutes ago, allowing wallet reset")
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
                let channels = try await LightningNodeService.shared.listChannels()
                if channels.count > 0 {
                    let closingChannel = channels[0]
                    try LightningNodeService.shared.closeChannel(userChannelId: closingChannel.userChannelId, counterPartyNodeId: closingChannel.counterpartyNodeId)
                    
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
                print("❌ [DEBUG] ResetApp - Channel closure failed with error: \(error)")
                print("❌ [DEBUG] ResetApp - Error type: \(type(of: error))")
                print("❌ [DEBUG] ResetApp - Error description: \(error.localizedDescription)")
                
                // Log additional error details if available
                if let nsError = error as NSError? {
                    print("❌ [DEBUG] ResetApp - NSError domain: \(nsError.domain)")
                    print("❌ [DEBUG] ResetApp - NSError code: \(nsError.code)")
                    print("❌ [DEBUG] ResetApp - NSError userInfo: \(nsError.userInfo)")
                }
                
                DispatchQueue.main.async {
                    self.showAlert(presentingController: self, title: Language.getWord(withID: "closechannel6"), message: Language.getWord(withID: "closechannel7"), buttons: [Language.getWord(withID: "cancel"), Language.getWord(withID: "forceclose")], actions: [nil, #selector(self.forceCloseChannel)])
                }
            }
        }
    }
    
    @objc func forceCloseChannel() {
        self.hideAlert()
        Task {
            do {
                let channels = try await LightningNodeService.shared.listChannels()
                if channels.count > 0 {
                    let closingChannel = channels[0]
                    
                    // Try force close (unilateral closure)
                    print("🔍 [DEBUG] ResetApp - Attempting force close for channel: \(closingChannel.userChannelId)")
                    try LightningNodeService.shared.forceCloseChannel(userChannelId: closingChannel.userChannelId, counterPartyNodeId: closingChannel.counterpartyNodeId)
                    
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
                print("❌ [DEBUG] ResetApp - Force close failed: \(error)")
                print("❌ [DEBUG] ResetApp - Force close error type: \(type(of: error))")
                print("❌ [DEBUG] ResetApp - Force close error description: \(error.localizedDescription)")
                
                DispatchQueue.main.async {
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
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: EnvironmentConfig.cacheKey(for: "mnemonic"))
        
        // Remove wallet from device and remove corresponding cached data.
        do {
            print("🔍 [DEBUG] ResetApp - Starting wallet reset cleanup")
            
            // Always try to stop the node first if it exists
            if LightningNodeService.shared.ldkNode != nil {
                print("🔍 [DEBUG] ResetApp - Stopping Lightning node")
                try LightningNodeService.shared.stop()
                print("🔍 [DEBUG] ResetApp - Lightning node stopped successfully")
            }
            
            // Always clean up documents directory
            print("🔍 [DEBUG] ResetApp - Cleaning up documents directory")
            try LightningNodeService.shared.deleteDocuments()
            print("🔍 [DEBUG] ResetApp - Documents directory cleaned successfully")
            
            // Reset node state to clear all references
            print("🔍 [DEBUG] ResetApp - Resetting node state")
            LightningNodeService.shared.resetNodeState()
            print("🔍 [DEBUG] ResetApp - Node state reset completed")
            
            // Clear all cached data
            print("🔍 [DEBUG] ResetApp - Clearing cached data")
            CacheManager.deleteClientInfo()
            print("🔍 [DEBUG] ResetApp - Cached data cleared successfully")
            
        } catch let error as NodeError {
            print("❌ [DEBUG] ResetApp - NodeError during cleanup: \(error.localizedDescription)")
            
            // Even if node stop fails, try to clean up documents
            do {
                print("🔍 [DEBUG] ResetApp - Attempting fallback document cleanup")
                try LightningNodeService.shared.deleteDocuments()
                print("🔍 [DEBUG] ResetApp - Fallback document cleanup successful")
            } catch {
                print("❌ [DEBUG] ResetApp - Fallback document cleanup failed: \(error.localizedDescription)")
            }
            
            CacheManager.deleteClientInfo()
            
        } catch {
            print("❌ [DEBUG] ResetApp - Error during cleanup: \(error.localizedDescription)")
            
            // Even if everything fails, try to clean up documents
            do {
                print("🔍 [DEBUG] ResetApp - Attempting final fallback document cleanup")
                try LightningNodeService.shared.deleteDocuments()
                print("🔍 [DEBUG] ResetApp - Final fallback document cleanup successful")
            } catch {
                print("❌ [DEBUG] ResetApp - Final fallback document cleanup failed: \(error.localizedDescription)")
            }
            
            CacheManager.deleteClientInfo()
        }
        
        // Hide signup view and launch create wallet flow
        // Since we've cleared the PIN, we need to manually show the create wallet flow
        self.homeVC!.view.alpha = 0
        self.hideSignup()
        
        // Launch signup on create wallet page after a delay to ensure cleanup is complete
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            print("🔍 [DEBUG] ResetApp - Launching signup after cleanup")
            self.launchSignup(onPage: 3) // Page 3 is create wallet
            self.showSignupView()
            
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
        print("🔍 [DEBUG] ResetApp - didCloseChannel() - Clearing channel cache and triggering sync")
        
        self.bittrWallet.lightningChannels = [ChannelDetails]()
        self.bittrWallet.bittrChannel = nil
        self.bittrWallet.satoshisLightning = 0
        
        if self.homeVC!.balanceLabel.alpha == 1 {
            self.homeVC!.setTotalSats(updateTableAfterConversion: false)
        }
        
        // Trigger a fresh sync to get updated channel data
        Task {
            do {
                print("🔍 [DEBUG] ResetApp - didCloseChannel() - Syncing wallet to get updated channel count")
                try LightningNodeService.shared.syncWallets()
                
                // Get fresh channel data
                let updatedChannels = try await LightningNodeService.shared.listChannels()
                print("🔍 [DEBUG] ResetApp - didCloseChannel() - Updated channel count: \(updatedChannels.count)")
                
                DispatchQueue.main.async {
                    // Update the cached channel data
                    self.bittrWallet.lightningChannels = updatedChannels
                    
                    // Update balance if needed
                    if self.homeVC!.balanceLabel.alpha == 1 {
                        self.homeVC!.setTotalSats(updateTableAfterConversion: false)
                    }
                    
                    print("🔍 [DEBUG] ResetApp - didCloseChannel() - Channel cache updated successfully")
                }
            } catch {
                print("❌ [DEBUG] ResetApp - didCloseChannel() - Error syncing after channel closure: \(error)")
            }
        }
    }
    
    func showSignupView() {
        
        // Show SignupVC.
        self.signupContainerView.alpha = 1
        
        // Raise Signup view back into view.
        UIView.animate(withDuration: 0.4, delay: 0, options: .curveEaseInOut) {
            NSLayoutConstraint.deactivate([self.signupBottom])
            self.signupBottom = NSLayoutConstraint(item: self.signupContainerView, attribute: .bottom, relatedBy: .equal, toItem: self.view, attribute: .bottom, multiplier: 1, constant: 0)
            NSLayoutConstraint.activate([self.signupBottom])
            self.blackSignupBackground.alpha = 1
            self.view.layoutIfNeeded()
        } completion: { finished in
            // Hide PinVC.
            self.pinContainerView.alpha = 0
        }
    }

}
