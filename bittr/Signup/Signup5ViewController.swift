//
//  Signup5ViewController.swift
//  bittr
//
//  Created by Tom Melters on 01/06/2023.
//

import UIKit

class Signup5ViewController: UIViewController, UITextFieldDelegate {

    
    override func viewDidLoad() {
        super.viewDidLoad()

    }
    
    
    func nextButtonTapped(enteredPin:String) {
        
        if enteredPin.count > 3 {
            let notificationDict:[String: Any] = ["page":"4"]
            NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "signupnext"), object: nil, userInfo: notificationDict) as Notification)
            
            let pinNotificationDict:[String: Any] = ["previouspin":enteredPin]
            NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "previouspin"), object: nil, userInfo: pinNotificationDict) as Notification)
        }
    }
    
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        
        if segue.identifier == "Signup5ToPin" {
            if let actualPinVC = segue.destination as? PinViewController {
                actualPinVC.embeddingView = "signup5"
                actualPinVC.upperViewController = self
            }
        }
    }
    
    
}
