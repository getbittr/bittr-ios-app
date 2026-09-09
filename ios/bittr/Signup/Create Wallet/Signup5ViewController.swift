//
//  Signup5ViewController.swift
//  bittr
//
//  Created by Tom Melters on 01/06/2023.
//

import UIKit

class Signup5ViewController: UIViewController, UITextFieldDelegate {

    // View for user to set their new pin.
    var coreVC:CoreViewController?
    var signupVC:SignupViewController?
    
    override func viewDidLoad() {
        super.viewDidLoad()
    }
    
    func nextButtonTapped(enteredPin:String) {
        
        // Check whether pin is more than 3 characters.
        if enteredPin.count > 3 {
            // Move to next page.
            self.signupVC?.moveToPage(8)
            
            // Send pin to Signup6VC.
            self.signupVC?.enteredPin = enteredPin
        }
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        
        if segue.identifier == "Signup5ToPin" {
            if let pinVC = segue.destination as? PinViewController {
                pinVC.embeddingView = .signup5
                pinVC.upperViewController = self
                pinVC.coreVC = self.coreVC ?? self.signupVC?.coreVC
            }
        }
    }
    
    
}
