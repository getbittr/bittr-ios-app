//
//  Restore3ViewController.swift
//  bittr
//
//  Created by Tom Melters on 29/08/2023.
//

import UIKit
//import KeychainSwift

class Restore3ViewController: UIViewController, UITextFieldDelegate {

    // Confirm new pin for restored wallet.
    
    var previousPIN:String?
    var coreVC:CoreViewController?
    var signupVC:SignupViewController?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.setPreviousPin()
    }
    
    func setPreviousPin() {
        
        if self.signupVC != nil {
            self.previousPIN = self.signupVC!.enteredPin
        }
    }
    
    
    func backButtonTapped() {
        
        self.signupVC?.moveToPage(1)
        
        /*let notificationDict:[String: Any] = ["page":"-3"]
         NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "signupnext"), object: nil, userInfo: notificationDict) as Notification)*/
    }
    
    func nextButtonTapped(enteredPin:String) {
        
        if let actualPreviousPin = self.previousPIN {
            
            if actualPreviousPin == enteredPin {
                CacheManager.storePin(pin: actualPreviousPin)
                // Ownership was just proven with the mnemonic, so clear any
                // accumulated wrong-PIN attempts — otherwise a Forgot-PIN
                // recovery would leave the user partway to the 10-attempt wipe.
                CacheManager.resetFailedPinAttempts()
                self.coreVC!.userHasSignedIn = true
                self.signupVC?.coreVC?.resettingPin = false
                self.coreVC!.buyVC?.registerIbanVC?.dismiss(animated: true)
                self.coreVC!.buyVC?.parseIbanEntities(uponPageLaunch: false)
                self.coreVC!.hideSignup()
                
            } else {
                self.showAlert(presentingController: self.signupVC?.coreVC ?? self.signupVC ?? self, title: Language.getWord(withID: "incorrectpin"), message: Language.getWord(withID: "repeatnumber"), buttons: [Language.getWord(withID: "okay")], actions: nil)
            }
        }
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        
        if segue.identifier == "Restore3ToPin" {
            if let pinVC = segue.destination as? PinViewController {
                pinVC.embeddingView = .restore3
                pinVC.upperViewController = self
                pinVC.coreVC = self.coreVC ?? self.signupVC?.coreVC
            }
        }
    }
    
}
