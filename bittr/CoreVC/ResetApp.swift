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
    
    
    func resetApp() {
    
        do {
            try LightningNodeService.shared.stop()
            
            keychain.synchronizable = true
            keychain.delete("")
            keychain.delete("pin")
            CacheManager.deleteClientInfo()
            
            do {
                try FileManager.default.removeItem(atPath: LightningStorage().getDocumentsDirectory())
            } catch {
                print(error.localizedDescription)
            }
            
            let notificationDict:[String: Any] = ["page":"restore"]
            NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "signupnext"), object: nil, userInfo: notificationDict) as Notification)
            
            self.signupContainerView.alpha = 1
            
            UIView.animate(withDuration: 0.4, delay: 0, options: .curveEaseInOut) {
                
                NSLayoutConstraint.deactivate([self.signupBottom])
                self.signupBottom = NSLayoutConstraint(item: self.signupContainerView, attribute: .bottom, relatedBy: .equal, toItem: self.view, attribute: .bottom, multiplier: 1, constant: 0)
                NSLayoutConstraint.activate([self.signupBottom])
                self.blackSignupBackground.alpha = 1
                self.view.layoutIfNeeded()
            } completion: { finished in
                
                self.pinContainerView.alpha = 0
            }
        } catch let error as NodeError {
            print(error.localizedDescription)
            
            // LDKNode wasn't active yet.
            keychain.synchronizable = true
            keychain.delete("")
            keychain.delete("pin")
            CacheManager.deleteClientInfo()
            
            do {
                try FileManager.default.removeItem(atPath: LightningStorage().getDocumentsDirectory())
            } catch {
                print(error.localizedDescription)
            }
            
            let notificationDict:[String: Any] = ["page":"restore"]
            NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "signupnext"), object: nil, userInfo: notificationDict) as Notification)
            
            self.signupContainerView.alpha = 1
            
            UIView.animate(withDuration: 0.4, delay: 0, options: .curveEaseInOut) {
                
                NSLayoutConstraint.deactivate([self.signupBottom])
                self.signupBottom = NSLayoutConstraint(item: self.signupContainerView, attribute: .bottom, relatedBy: .equal, toItem: self.view, attribute: .bottom, multiplier: 1, constant: 0)
                NSLayoutConstraint.activate([self.signupBottom])
                self.blackSignupBackground.alpha = 1
                self.view.layoutIfNeeded()
            } completion: { finished in
                
                self.pinContainerView.alpha = 0
            }
            
        } catch {
            print(error.localizedDescription)
        }
    }

}
