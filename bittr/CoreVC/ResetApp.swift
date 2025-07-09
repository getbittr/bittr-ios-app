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
                        // Wallet cannot be reset with open channels.
                        self.showAlert(presentingController: self, title: Language.getWord(withID: "restorewallet"), message: Language.getWord(withID: "restorewallet4"), buttons: [Language.getWord(withID: "cancel"), Language.getWord(withID: "closechannel")], actions: [nil, #selector(self.closeChannelAlert)])
                    } else {
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
                    
                    // Successful channel closure.
                    DispatchQueue.main.async {
                        self.didCloseChannel()
                        self.showAlert(presentingController: self, title: Language.getWord(withID: "closechannel"), message: Language.getWord(withID: "closechannel3"), buttons: [Language.getWord(withID: "okay")], actions: [#selector(self.channelClosedProceedWithReset)])
                    }
                } else {
                    // No channels to close, proceed with reset
                    DispatchQueue.main.async {
                        self.performWalletReset(nodeIsRunning: true)
                    }
                }
            } catch {
                // Unsuccessful channel closure.
                DispatchQueue.main.async {
                    self.showAlert(presentingController: self, title: Language.getWord(withID: "closechannel"), message: Language.getWord(withID: "closechannel4"), buttons: [Language.getWord(withID: "okay")], actions: nil)
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
        
        // Clear mnemonic from cache
        let defaults = UserDefaults.standard
        if UserDefaults.standard.value(forKey: "envkey") as? Int == 0 {
            defaults.removeObject(forKey: "mnemonic")
        } else {
            defaults.removeObject(forKey: "prodmnemonic")
        }
        
        // Remove wallet from device and remove corresponding cached data.
        do {
            if nodeIsRunning == false {
                try FileManager.default.deleteAllContentsInDocumentsDirectory()
            } else {
                try LightningNodeService.shared.stop()
                try LightningNodeService.shared.deleteDocuments()
            }
            
            CacheManager.deleteClientInfo()
        } catch let error as NodeError {
            print(error.localizedDescription)
            
            CacheManager.deleteClientInfo()
            
            do {
                try FileManager.default.removeItem(atPath: LightningStorage().getDocumentsDirectory())
            } catch {
                print(error.localizedDescription)
            }
            
        } catch {
            print(error.localizedDescription)
            
            CacheManager.deleteClientInfo()
            
            do {
                try FileManager.default.removeItem(atPath: LightningStorage().getDocumentsDirectory())
            } catch {
                print(error.localizedDescription)
            }
        }
        
        // Hide signup view and launch create wallet flow
        // Since we've cleared the PIN, we need to manually show the create wallet flow
        self.hideSignup()
        
        // Launch signup on create wallet page after a short delay to ensure hideSignup completes
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.launchSignup(onPage: 3) // Page 3 is create wallet
            self.showSignupView()
        }
    }
    
    func didCloseChannel() {
        
        self.lightningChannels = nil
        self.bittrChannel = nil
        self.lightningBalanceInSats = 0
        
        if self.homeVC!.balanceLabel.alpha == 1 {
            self.homeVC!.setTotalSats(updateTableAfterConversion: false)
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
