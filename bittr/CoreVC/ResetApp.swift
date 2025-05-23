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
        
        // Launch signup for menmonic check.
        self.launchSignup(onPage: 3)
        
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
        
        // Remove wallet from device and remove corresponding cached data.
        
        self.launchSignup(onPage: 2)
    
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
