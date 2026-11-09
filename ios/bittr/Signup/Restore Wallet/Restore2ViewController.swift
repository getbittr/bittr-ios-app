//
//  Restore2ViewController.swift
//  bittr
//
//  Created by Tom Melters on 29/08/2023.
//

import UIKit

class Restore2ViewController: UIViewController, UITextFieldDelegate {

    // Set pin for restored wallet.
    var coreVC:CoreViewController?
    weak var signupVC:SignupViewController?
    
    override func viewDidLoad() {
        super.viewDidLoad()
    }
    
    func nextButtonTapped(enteredPin:String) {
        if enteredPin.count > 3 {
            self.signupVC?.enteredPin = enteredPin
            self.signupVC?.moveToPage(0)
        }
    }
    
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        
        if segue.identifier == "Restore2ToPin" {
            if let pinVC = segue.destination as? PinViewController {
                pinVC.embeddingView = .restore2
                pinVC.upperViewController = self
                pinVC.coreVC = self.coreVC ?? self.signupVC?.coreVC
            }
        }
    }
    
}
