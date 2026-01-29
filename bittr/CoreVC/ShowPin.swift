//
//  ShowPin.swift
//  bittr
//
//  Created by Tom Melters on 08/02/2024.
//

import UIKit

extension CoreViewController {

    func correctPin(spinner:UIActivityIndicatorView) {
        
        // The correct pin has been entered in the PinVC and the wallet is ready to be synced and shown.
        self.userHasSignedIn = true
        
        // Start wallet.
        self.startLightning()
        
        // Lower pin view.
        self.lowerPinView(spinner: spinner)
    }
    
    
    func lowerPinView(spinner:UIActivityIndicatorView) {
        
        UIView.animate(withDuration: 0.4, delay: 0, options: .curveEaseInOut) {
            NSLayoutConstraint.deactivate([self.pinBottom])
            self.pinBottom = NSLayoutConstraint(item: self.pinContainerView, attribute: .top, relatedBy: .equal, toItem: self.view, attribute: .bottom, multiplier: 1, constant: 0)
            NSLayoutConstraint.activate([self.pinBottom])
            self.blackSignupBackground.alpha = 0
            self.view.layoutIfNeeded()
        } completion: { finished in
            self.pinContainerView.alpha = 0
            spinner.stopAnimating()
            
            if self.lightningNotification != nil || self.needsToHandleURI() {
                // A notification will be handled after syncing the wallet.
                self.pendingLabel.text = Language.getWord(withID: "syncingwallet3")
                self.showPendingView()
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    self.showSyncView()
                }
            }
        }
    }
    
    
    func showSignup() {
        
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
    
    
    @objc func hideSignup() {
        
        // Hide SignupVC.
        UIView.animate(withDuration: 0.4, delay: 0, options: .curveEaseInOut) {
            NSLayoutConstraint.deactivate([self.signupBottom])
            self.signupBottom = NSLayoutConstraint(item: self.signupContainerView, attribute: .top, relatedBy: .equal, toItem: self.view, attribute: .bottom, multiplier: 1, constant: 0)
            NSLayoutConstraint.activate([self.signupBottom])
            self.blackSignupBackground.alpha = 0
            self.view.layoutIfNeeded()
        } completion: { finished in
            // Remove signup view from container.
            self.signupContainerView.alpha = 0
            if self.signupContainerView.subviews.count == 1 {
                self.signupContainerView.subviews[0].removeFromSuperview()
            }
            
            if self.walletHasSynced {
                // Check for pending URIs after user signs in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.checkForPendingURIs()
                }
            }
        }
    }
    
}
