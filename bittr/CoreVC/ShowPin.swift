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
        
        // Load client details.
        self.setClient()
        
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
            self.didBecomeVisible = true
            if self.needsToHandleNotification == true {
                // A notification will be handled after syncing the wallet.
                self.pendingLabel.text = Language.getWord(withID: "syncingwallet3")
                self.pendingSpinner.startAnimating()
                self.pendingView.alpha = 1
                self.blackSignupBackground.alpha = 0.2
            }
        }
    }
    
    
    func setClient() {
        
        var envKey = "proddevice"
        if UserDefaults.standard.value(forKey: "envkey") as? Int == 0 {
            envKey = "device"
        }
        
        let deviceDict = UserDefaults.standard.value(forKey: envKey) as? NSDictionary
        if let actualDeviceDict = deviceDict {
            // Client exists in cache.
            let clients:[Client] = CacheManager.parseDevice(deviceDict: actualDeviceDict)
            self.client = clients[0]
        }
        
    }
    
    
    @objc func hideSignup() {
        
        // Hide signup view.
        UIView.animate(withDuration: 0.4, delay: 0, options: .curveEaseInOut) {
            NSLayoutConstraint.deactivate([self.signupBottom])
            self.signupBottom = NSLayoutConstraint(item: self.signupContainerView, attribute: .top, relatedBy: .equal, toItem: self.view, attribute: .bottom, multiplier: 1, constant: 0)
            NSLayoutConstraint.activate([self.signupBottom])
            self.blackSignupBackground.alpha = 0
            self.view.layoutIfNeeded()
        } completion: { finished in
            self.signupContainerView.alpha = 0
            self.didBecomeVisible = true
            
            // Remove signup view from container.
            if self.signupContainerView.subviews.count == 1 {
                self.signupContainerView.subviews[0].removeFromSuperview()
            }
        }
    }
    
}
