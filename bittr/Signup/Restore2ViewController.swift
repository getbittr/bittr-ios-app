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
    var signupVC:SignupViewController?
    
    override func viewDidLoad() {
        super.viewDidLoad()
    }
    
    func nextButtonTapped(enteredPin:String) {
        
        if enteredPin.count > 3 {
            
            self.signupVC?.enteredPin = enteredPin
            self.signupVC?.moveToPage(0)
            
            /*let notificationDict:[String: Any] = ["page":"-4"]
            NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "signupnext"), object: nil, userInfo: notificationDict) as Notification)
            
            let pinNotificationDict:[String: Any] = ["previouspin":enteredPin]
            NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "previouspin"), object: nil, userInfo: pinNotificationDict) as Notification)*/
        }
    }
    
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        
        if segue.identifier == "Restore2ToPin" {
            if let actualPinVC = segue.destination as? PinViewController {
                actualPinVC.embeddingView = "restore2"
                actualPinVC.upperViewController = self
            }
        }
    }
    
}
