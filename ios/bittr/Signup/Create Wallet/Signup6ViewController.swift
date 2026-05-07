//
//  Signup6ViewController.swift
//  bittr
//
//  Created by Tom Melters on 01/06/2023.
//

import UIKit
import Sentry

class Signup6ViewController: UIViewController, UITextFieldDelegate {

    // View for user to confirm their new pin.
    var coreVC:CoreViewController?
    var signupVC:SignupViewController?
    
    var previousPIN:String?
    
    override func viewDidLoad() {
        super.viewDidLoad()
    }
    
    func setPreviousPin() {
        
        if self.signupVC?.enteredPin != nil, self.signupVC!.enteredPin != "" {
            self.previousPIN = self.signupVC!.enteredPin
        }
    }
    
    func backButtonTapped() {
        
        self.signupVC?.enteredPin = ""
        self.signupVC?.moveToPage(7)
    }
    
    func nextButtonTapped(enteredPin:String) {
        
        // Check whether the confirmed pin is correct.
        
        self.setPreviousPin()
        if let actualPreviousPin = self.previousPIN {
            if actualPreviousPin == enteredPin {
                // Pin is correct.
                self.signupVC?.coreVC?.userHasSignedIn = true
                self.signupVC?.enteredPin = ""
                
                // Move to next page.
                self.signupVC?.moveToPage(9)
                
                // Store pin in cache.
                CacheManager.storePin(pin: actualPreviousPin)
                
                // Count successful wallet creation.
                SentrySDK.metrics.count(key: "app.launch.newwallet.success")
                
                // Start wallet.
                Task {
                    await self.signupVC?.coreVC?.startWallet()
                }
            } else {
                // Pin is incorrect.
                self.showAlert(presentingController: self.signupVC?.coreVC ?? self.signupVC ?? self, title: Language.getWord(withID: "incorrectpin"), message: Language.getWord(withID: "repeatnumber"), buttons: [Language.getWord(withID: "okay")], actions: nil)
            }
        }
    }
    
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        
        if segue.identifier == "Signup6ToPin" {
            if let pinVC = segue.destination as? PinViewController {
                pinVC.embeddingView = .signup6
                pinVC.upperViewController = self
                pinVC.coreVC = self.coreVC ?? self.signupVC?.coreVC
            }
        }
    }
    
}
