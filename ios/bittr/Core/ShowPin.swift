//
//  ShowPin.swift
//  bittr
//
//  Created by Tom Melters on 08/02/2024.
//

import UIKit

extension CoreViewController {
    
    func lowerPinView(spinner:UIActivityIndicatorView) {
        
        UIView.animate(withDuration: 0.8, delay: 0, usingSpringWithDamping: 0.75, initialSpringVelocity: 0, options: .curveEaseInOut) {
            NSLayoutConstraint.deactivate([self.pinBottom, self.homeContainerTop, self.menuBarBottom])
            self.pinBottom = NSLayoutConstraint(item: self.pinContainerView, attribute: .bottom, relatedBy: .equal, toItem: self.view, attribute: .top, multiplier: 1, constant: 0)
            self.homeContainerTop = NSLayoutConstraint(item: self.homeContainerView, attribute: .top, relatedBy: .equal, toItem: self.view, attribute: .top, multiplier: 1, constant: 0)
            self.menuBarBottom = NSLayoutConstraint(item: self.menuBarContainer, attribute: .bottom, relatedBy: .equal, toItem: self.view.safeAreaLayoutGuide, attribute: .bottom, multiplier: 1, constant: 10)
            NSLayoutConstraint.activate([self.pinBottom, self.homeContainerTop, self.menuBarBottom])
            self.view.layoutIfNeeded()
        } completion: { finished in
            self.pinContainerView.alpha = 0
            spinner.stopAnimating()
            
            if self.lightningNotification != nil || self.needsToHandleURI() {
                // A notification will be handled after syncing the wallet.
                self.showLoading(message: Language.getWord(withID: "syncingwallet3"))
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
            self.view.layoutIfNeeded()
        } completion: { finished in
            // Hide PinVC.
            self.pinContainerView.alpha = 0
        }
    }
    
    
    func hideSignup() {
        
        // Hide SignupVC.
        UIView.animate(withDuration: 0.4, delay: 0, options: .curveEaseInOut) {
            NSLayoutConstraint.deactivate([self.signupBottom])
            self.signupBottom = NSLayoutConstraint(item: self.signupContainerView, attribute: .top, relatedBy: .equal, toItem: self.view, attribute: .bottom, multiplier: 1, constant: 0)
            NSLayoutConstraint.activate([self.signupBottom])
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
