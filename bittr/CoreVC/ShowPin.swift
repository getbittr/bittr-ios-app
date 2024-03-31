//
//  ShowPin.swift
//  bittr
//
//  Created by Tom Melters on 08/02/2024.
//

import UIKit

extension CoreViewController {

    func correctPin(spinner:UIActivityIndicatorView) {
        
        // Step 2.
        
        if let actualHomeVC = self.homeVC {
            actualHomeVC.fixGraphViewHeight()
            actualHomeVC.setClient()
        }
        
        //NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "fixgraph"), object: nil, userInfo: nil) as Notification)
        //NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "setclient"), object: nil, userInfo: nil) as Notification)
        
        startLightning()
        
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
                
                self.pendingLabel.text = "syncing wallet"
                self.pendingSpinner.startAnimating()
                self.pendingView.alpha = 1
                self.blackSignupBackground.alpha = 0.2
            }
        }
    }
    
    
    @objc func hideSignup() {
        
        if let actualHomeVC = self.homeVC {
            actualHomeVC.fixGraphViewHeight()
        }
        //NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "fixgraph"), object: nil, userInfo: nil) as Notification)
        
        UIView.animate(withDuration: 0.4, delay: 0, options: .curveEaseInOut) {
            
            NSLayoutConstraint.deactivate([self.signupBottom])
            self.signupBottom = NSLayoutConstraint(item: self.signupContainerView, attribute: .top, relatedBy: .equal, toItem: self.view, attribute: .bottom, multiplier: 1, constant: 0)
            NSLayoutConstraint.activate([self.signupBottom])
            self.blackSignupBackground.alpha = 0
            self.view.layoutIfNeeded()
        } completion: { finished in
            self.signupContainerView.alpha = 0
            self.didBecomeVisible = true
        }
    }
    
}
