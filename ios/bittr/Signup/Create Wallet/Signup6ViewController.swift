//
//  Signup6ViewController.swift
//  bittr
//
//  Created by Tom Melters on 01/06/2023.
//

import UIKit

class Signup6ViewController: UIViewController, UITextFieldDelegate {

    // View for user to confirm their new pin.
    var coreVC:CoreViewController?
    weak var signupVC:SignupViewController?
    
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
                
                // Store pin in cache.
                do {
                    try CacheManager.storePin(pin: actualPreviousPin)
                } catch {
                    self.showAlert(title: Language.getWord(withID: "error"), message: Language.getWord(withID: "pinsavefail"), buttons: [.dismiss(Language.getWord(withID: "okay"))])
                    return
                }
                
                self.signupVC?.coreVC?.userHasSignedIn = true
                self.signupVC?.enteredPin = ""
                
                // Move to next page.
                self.signupVC?.moveToPage(9)
                
                // Count successful wallet creation.
                SentryManager.countMetric("app.launch.newwallet.success")
                
                // Start wallet.
                self.signupVC?.coreVC?.startWallet()
            } else {
                // Pin is incorrect.
                self.showAlert(title: Language.getWord(withID: "incorrectpin"), message: Language.getWord(withID: "repeatnumber"), buttons: [.dismiss(Language.getWord(withID: "okay"))])
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
