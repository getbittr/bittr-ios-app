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
    }
    
    func nextButtonTapped(enteredPin:String) {
        
        guard let previousPIN, enteredPin == previousPIN else {
            self.showAlert(title: Language.getWord(withID: "incorrectpin"), message: Language.getWord(withID: "repeatnumber"), buttons: [.dismiss(Language.getWord(withID: "okay"))])
            return
        }
        
        CacheManager.storePin(pin: previousPIN)
        CacheManager.resetFailedPinAttempts()
        
        self.coreVC!.userHasSignedIn = true
        self.signupVC?.coreVC?.resettingPin = false
        self.coreVC!.buyVC?.registerIbanVC?.dismiss(animated: true)
        self.coreVC!.buyVC?.parseIbanEntities(uponPageLaunch: false)
        self.coreVC!.fromSignupToHome()
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
