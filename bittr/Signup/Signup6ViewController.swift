//
//  Signup6ViewController.swift
//  bittr
//
//  Created by Tom Melters on 01/06/2023.
//

import UIKit
//import KeychainSwift

class Signup6ViewController: UIViewController, UITextFieldDelegate {

    // View for user to confirm their new pin.
    var coreVC:CoreViewController?
    
    var previousPIN:String?
    
    override func viewDidLoad() {
        super.viewDidLoad()

        // Set notification observers.
        NotificationCenter.default.addObserver(self, selector: #selector(setPreviousPin), name: NSNotification.Name(rawValue: "previouspin"), object: nil)
    }
    
    @objc func setPreviousPin(notification:NSNotification) {
        
        if let userInfo = notification.userInfo as [AnyHashable:Any]? {
            if let previousNumber = userInfo["previouspin"] as? String {
                
                self.previousPIN = previousNumber
            }
        }
    }
    
    
    func backButtonTapped() {
        
        let notificationDict:[String: Any] = ["page":"3"]
         NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "signupnext"), object: nil, userInfo: notificationDict) as Notification)
    }
    
    func nextButtonTapped(enteredPin:String) {
        
        // Check whether the confirmed pin is correct.
        
        if let actualPreviousPin = self.previousPIN {
            if actualPreviousPin == enteredPin {
                // Pin is correct.
                // Start wallet.
                if self.coreVC == nil { print("CoreVC nil in Signup 6.") }
                self.coreVC?.startLightning()
                // Move to next page.
                let notificationDict:[String: Any] = ["page":"5"]
                 NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "signupnext"), object: nil, userInfo: notificationDict) as Notification)
                
                // Store pin in cache.
                CacheManager.storePin(pin: actualPreviousPin)
                
            } else {
                // Pin is incorrect.
                self.showAlert(title: Language.getWord(withID: "incorrectpin"), message: Language.getWord(withID: "repeatnumber"), buttons: [Language.getWord(withID: "okay")])
            }
        }
    }
    
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        
        if segue.identifier == "Signup6ToPin" {
            if let actualPinVC = segue.destination as? PinViewController {
                actualPinVC.embeddingView = "signup6"
                actualPinVC.upperViewController = self
            }
        }
    }
    
}
