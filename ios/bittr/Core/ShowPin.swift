//
//  ShowPin.swift
//  bittr
//
//  Created by Tom Melters on 08/02/2024.
//

import UIKit

extension CoreViewController {
    
    @objc func appDidEnterBackground() {
        // Keep track of when the app was backgrounded.
        self.backgroundedAt = self.userHasSignedIn ? Date() : nil
        // Interrupt BDK scan if ongoing.
        BitcoinManager.shared.markBdkScanInterrupted()
    }
    
    @objc func appWillEnterForeground() {
        self.retryOnchainScanIfNeeded()
        guard let wentAway = self.backgroundedAt else { return }
        self.backgroundedAt = nil
        
        // If app was backgrounded for more than 120s, user needs to reauthenticate.
        guard Date().timeIntervalSince(wentAway) >= 120 else { return }
        self.lockForReauthentication()
    }
    
    func retryOnchainScanIfNeeded() {
        guard BitcoinManager.shared.bdkWallet != nil,
                !BitcoinManager.shared.bdkWalletHasBeenScanned else { return }
        Log.info("No BDK full scan has succeeded yet. Retrying it on foreground.")
        
        BitcoinManager.shared.didSyncBdkWallet { hasBeenSynced in
            guard hasBeenSynced else { return }
            Log.info("Retried BDK full scan succeeded.")
            
            // Restart background syncs.
            if self.walletSync == nil {
                self.walletSync = BackgroundSync()
                self.walletSync!.start()
            }
            
            // Update labels.
            self.homeVC?.sendVC?.setSendAllLabel()
            self.homeVC?.moveVC?.swapVC?.calculateSendableAmount()
        }
    }
    
    func lockForReauthentication() {
        guard self.userHasSignedIn, self.currentPage == .home else { return }
        guard CacheManager.hasPin() else { return }
        guard !self.resettingPin, !self.removingWalletForIncorrectPin, !self.isRemovalInFlight else { return }
        Log.info("App was backgrounded for longer than 120s. Asking for the PIN again.")
        
        self.view.endEditing(true)
        
        // Close any active segues.
        if self.presentedViewController != nil { self.dismiss(animated: false) }
        self.hideSettings()
        
        // Prepare and show PinVC.
        self.pinVC?.clearPinField()
        self.userHasSignedIn = false
        UIView.performWithoutAnimation { self.showPin() }
    }
    
    func showPin(completion: (() -> Void)? = nil) {
        guard self.currentPage != .pin else {
            completion?()
            return
        }
        
        if self.currentPage == .signup {
            // Place PinVC above SignupVC.
            NSLayoutConstraint.deactivate([self.pinBottom])
            self.pinBottom = NSLayoutConstraint(item: self.pinContainerView, attribute: .bottom, relatedBy: .equal, toItem: self.view, attribute: .top, multiplier: 1, constant: 0)
            NSLayoutConstraint.activate([self.pinBottom])
            self.view.layoutIfNeeded()
            self.pinContainerView.alpha = 1
            
            // Lower SignupVC out of view, and PinVC into view.
            UIView.animate(withDuration: 0.8, delay: 0, usingSpringWithDamping: 0.75, initialSpringVelocity: 0, options: .curveEaseInOut) {
                NSLayoutConstraint.deactivate([self.signupBottom, self.pinBottom])
                self.pinBottom = NSLayoutConstraint(item: self.pinContainerView, attribute: .bottom, relatedBy: .equal, toItem: self.view, attribute: .bottom, multiplier: 1, constant: 0)
                self.signupBottom = NSLayoutConstraint(item: self.signupContainerView, attribute: .top, relatedBy: .equal, toItem: self.view, attribute: .bottom, multiplier: 1, constant: 0)
                NSLayoutConstraint.activate([self.signupBottom, self.pinBottom])
                self.view.layoutIfNeeded()
            } completion: { finished in
                
                // Reset signup positioning.
                self.signupContainerView.alpha = 0
                NSLayoutConstraint.deactivate([self.signupBottom])
                self.signupBottom = NSLayoutConstraint(item: self.signupContainerView, attribute: .bottom, relatedBy: .equal, toItem: self.view, attribute: .bottom, multiplier: 1, constant: 0)
                NSLayoutConstraint.activate([self.signupBottom])
                self.view.layoutIfNeeded()
                
                self.currentPage = .pin
                self.hideSignup()
                completion?()
            }
        } else {
            // Slide from Home back to Pin.
            self.pinContainerView.alpha = 1
            UIView.animate(withDuration: 0.8, delay: 0, usingSpringWithDamping: 0.75, initialSpringVelocity: 0, options: .curveEaseInOut) {
                NSLayoutConstraint.deactivate([self.signupBottom, self.pinBottom, self.homeContainerTop, self.menuBarBottom])
                self.pinBottom = NSLayoutConstraint(item: self.pinContainerView, attribute: .bottom, relatedBy: .equal, toItem: self.view, attribute: .bottom, multiplier: 1, constant: 0)
                self.signupBottom = NSLayoutConstraint(item: self.signupContainerView, attribute: .bottom, relatedBy: .equal, toItem: self.view, attribute: .bottom, multiplier: 1, constant: 0)
                self.homeContainerTop = NSLayoutConstraint(item: self.homeContainerView, attribute: .top, relatedBy: .equal, toItem: self.view, attribute: .bottom, multiplier: 1, constant: 0)
                self.menuBarBottom = NSLayoutConstraint(item: self.menuBarContainer, attribute: .bottom, relatedBy: .equal, toItem: self.homeContainerView, attribute: .bottom, multiplier: 1, constant: -30)
                NSLayoutConstraint.activate([self.signupBottom, self.pinBottom, self.homeContainerTop, self.menuBarBottom])
                self.view.layoutIfNeeded()
            } completion: { finished in
                self.userHasSignedIn = false
                self.currentPage = .pin
                completion?()
            }
        }
    }
    
    func fromPinToHome() {
        self.hidePinAndSignup()
        
        // Wait for 0.8 second animation.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            self.pinContainerView.alpha = 0
            
            if self.lightningNotification != nil || self.needsToHandleURI() {
                // A notification will be handled after syncing the wallet.
                self.showLoading(message: Language.getWord(withID: "syncingwallet3"))
            }
        }
    }
    
    
    func showSignup() {
        // Slide from HomeVC or PinVC to SignupVC.
        
        // Show SignupVC.
        self.signupContainerView.alpha = 1
        
        if self.currentPage == .home {
            // We're navigating from Home to Signup.
            
            UIView.animate(withDuration: 0.8, delay: 0, usingSpringWithDamping: 0.75, initialSpringVelocity: 0, options: .curveEaseInOut) {
                NSLayoutConstraint.deactivate([self.signupBottom, self.pinBottom, self.homeContainerTop, self.menuBarBottom])
                self.pinBottom = NSLayoutConstraint(item: self.pinContainerView, attribute: .bottom, relatedBy: .equal, toItem: self.view, attribute: .bottom, multiplier: 1, constant: 0)
                self.signupBottom = NSLayoutConstraint(item: self.signupContainerView, attribute: .bottom, relatedBy: .equal, toItem: self.view, attribute: .bottom, multiplier: 1, constant: 0)
                self.homeContainerTop = NSLayoutConstraint(item: self.homeContainerView, attribute: .top, relatedBy: .equal, toItem: self.view, attribute: .bottom, multiplier: 1, constant: 0)
                self.menuBarBottom = NSLayoutConstraint(item: self.menuBarContainer, attribute: .bottom, relatedBy: .equal, toItem: self.homeContainerView, attribute: .bottom, multiplier: 1, constant: -30)
                NSLayoutConstraint.activate([self.signupBottom, self.pinBottom, self.homeContainerTop, self.menuBarBottom])
                self.view.layoutIfNeeded()
            }
            self.currentPage = .signup
        } else if self.currentPage == .pin {
            // We're navigating from PIN to Signup.
            
            // Place SignupVC underneath the PinVC.
            NSLayoutConstraint.deactivate([self.signupBottom])
            self.signupBottom = NSLayoutConstraint(item: self.signupContainerView, attribute: .top, relatedBy: .equal, toItem: self.view, attribute: .bottom, multiplier: 1, constant: 0)
            NSLayoutConstraint.activate([self.signupBottom])
            self.view.layoutIfNeeded()
            
            // Raise PinVC out of view, and SignupVC into view.
            UIView.animate(withDuration: 0.8, delay: 0, usingSpringWithDamping: 0.75, initialSpringVelocity: 0, options: .curveEaseInOut) {
                NSLayoutConstraint.deactivate([self.signupBottom, self.pinBottom])
                self.pinBottom = NSLayoutConstraint(item: self.pinContainerView, attribute: .bottom, relatedBy: .equal, toItem: self.view, attribute: .top, multiplier: 1, constant: 0)
                self.signupBottom = NSLayoutConstraint(item: self.signupContainerView, attribute: .bottom, relatedBy: .equal, toItem: self.view, attribute: .bottom, multiplier: 1, constant: 0)
                NSLayoutConstraint.activate([self.signupBottom, self.pinBottom])
                self.view.layoutIfNeeded()
            } completion: { finished in
                
                // Reset pin positioning.
                self.pinContainerView.alpha = 0
                NSLayoutConstraint.deactivate([self.pinBottom])
                self.pinBottom = NSLayoutConstraint(item: self.pinContainerView, attribute: .bottom, relatedBy: .equal, toItem: self.view, attribute: .bottom, multiplier: 1, constant: 0)
                NSLayoutConstraint.activate([self.pinBottom])
                self.view.layoutIfNeeded()
            }
            self.currentPage = .signup
        }
    }
    
    func fromSignupToHome() {
        // Move from Signup to Home.
        self.hidePinAndSignup()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            self.hideSignup()
        }
    }
    
    
    func hideSignup() {
        
        // Remove signup view from container.
        self.signupContainerView.alpha = 0
        for eachSubview in self.signupContainerView.subviews {
            eachSubview.removeFromSuperview()
        }
        
        if self.walletHasSynced {
            // Check for pending URIs after user signs in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.checkForPendingURIs()
            }
        }
    }
    
    func hidePinAndSignup() {
        self.currentPage = .home
        UIView.animate(withDuration: 0.8, delay: 0, usingSpringWithDamping: 0.75, initialSpringVelocity: 0, options: .curveEaseInOut) {
            NSLayoutConstraint.deactivate([self.signupBottom, self.pinBottom, self.homeContainerTop, self.menuBarBottom])
            self.pinBottom = NSLayoutConstraint(item: self.pinContainerView, attribute: .bottom, relatedBy: .equal, toItem: self.view, attribute: .top, multiplier: 1, constant: 0)
            self.signupBottom = NSLayoutConstraint(item: self.signupContainerView, attribute: .bottom, relatedBy: .equal, toItem: self.view, attribute: .top, multiplier: 1, constant: 0)
            self.homeContainerTop = NSLayoutConstraint(item: self.homeContainerView, attribute: .top, relatedBy: .equal, toItem: self.view, attribute: .top, multiplier: 1, constant: 0)
            self.menuBarBottom = NSLayoutConstraint(item: self.menuBarContainer, attribute: .bottom, relatedBy: .equal, toItem: self.view.safeAreaLayoutGuide, attribute: .bottom, multiplier: 1, constant: 10)
            NSLayoutConstraint.activate([self.signupBottom, self.pinBottom, self.homeContainerTop, self.menuBarBottom])
            self.view.layoutIfNeeded()
        }
    }
    
}

enum CurrentPage {
    case home
    case pin
    case signup
}
