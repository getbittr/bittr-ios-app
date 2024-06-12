//
//  Signup6ViewController.swift
//  bittr
//
//  Created by Tom Melters on 01/06/2023.
//

import UIKit
//import KeychainSwift

class Signup6ViewController: UIViewController, UITextFieldDelegate {

    var previousPIN:String?
    
    override func viewDidLoad() {
        super.viewDidLoad()

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
        
        if let actualPreviousPin = self.previousPIN {
            
            if actualPreviousPin == enteredPin {
                
                NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "startlightning"), object: nil, userInfo: nil) as Notification)
                let notificationDict:[String: Any] = ["page":"5"]
                 NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "signupnext"), object: nil, userInfo: notificationDict) as Notification)
                
                CacheManager.storePin(pin: actualPreviousPin)
                
            } else {
                let alert = UIAlertController(title: "Incorrect PIN", message: "Repeat the same number.", preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "Okay", style: .cancel, handler: nil))
                self.present(alert, animated: true)
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
