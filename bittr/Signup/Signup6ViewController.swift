//
//  Signup6ViewController.swift
//  bittr
//
//  Created by Tom Melters on 01/06/2023.
//

import UIKit

class Signup6ViewController: UIViewController, UITextFieldDelegate {

    @IBOutlet weak var pinTextField: UITextField!
    @IBOutlet weak var nextButton: UIButton!
    @IBOutlet weak var saveView: UIView!
    @IBOutlet weak var backButton: UIButton!
    
    @IBOutlet weak var button1: UIButton!
    @IBOutlet weak var button2: UIButton!
    @IBOutlet weak var button3: UIButton!
    @IBOutlet weak var button4: UIButton!
    @IBOutlet weak var button5: UIButton!
    @IBOutlet weak var button6: UIButton!
    @IBOutlet weak var button7: UIButton!
    @IBOutlet weak var button8: UIButton!
    @IBOutlet weak var button9: UIButton!
    @IBOutlet weak var button0: UIButton!
    @IBOutlet weak var buttonBackspace: UIButton!
    
    var previousPIN:String?
    
    @IBOutlet weak var centerView: UIView!
    @IBOutlet weak var contentView: UIView!
    @IBOutlet weak var centerViewCenterY: NSLayoutConstraint!
    @IBOutlet weak var contentViewHeight: NSLayoutConstraint!
    
    override func viewDidLoad() {
        super.viewDidLoad()

        button1.setTitle("", for: .normal)
        button2.setTitle("", for: .normal)
        button3.setTitle("", for: .normal)
        button4.setTitle("", for: .normal)
        button5.setTitle("", for: .normal)
        button6.setTitle("", for: .normal)
        button7.setTitle("", for: .normal)
        button8.setTitle("", for: .normal)
        button9.setTitle("", for: .normal)
        button0.setTitle("", for: .normal)
        nextButton.setTitle("", for: .normal)
        buttonBackspace.setTitle("", for: .normal)
        backButton.setTitle("", for: .normal)
        
        saveView.layer.cornerRadius = 13
        
        pinTextField.delegate = self
        
        NotificationCenter.default.addObserver(self, selector: #selector(setPreviousPin), name: NSNotification.Name(rawValue: "previouspin"), object: nil)
    }
    
    @objc func setPreviousPin(notification:NSNotification) {
        
        if let userInfo = notification.userInfo as [AnyHashable:Any]? {
            if let previousNumber = userInfo["previouspin"] as? String {
                
                self.previousPIN = previousNumber
            }
        }
    }
    
    @IBAction func numberButtonTapped(_ sender: UIButton) {
        
        pinTextField.insertText(String(sender.tag))
    }
    
    @IBAction func backspaceButtonTapped(_ sender: UIButton) {
        
        pinTextField.deleteBackward()
    }
    
    @IBAction func backButtonTapped(_ sender: UIButton) {
        
        let notificationDict:[String: Any] = ["page":sender.accessibilityIdentifier]
         NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "signupnext"), object: nil, userInfo: notificationDict) as Notification)
    }
    
    @IBAction func nextButtonTapped(_ sender: UIButton) {
        
        if let actualPreviousPin = self.previousPIN {
            
            if actualPreviousPin == self.pinTextField.text {
                let notificationDict:[String: Any] = ["page":sender.accessibilityIdentifier]
                 NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "signupnext"), object: nil, userInfo: notificationDict) as Notification)
                //NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "restorewallet"), object: nil, userInfo: nil) as Notification)
            } else {
                let alert = UIAlertController(title: "Incorrect PIN", message: "Repeat the same number.", preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "Okay", style: .cancel, handler: nil))
                self.present(alert, animated: true)
            }
        }
    }
    
    override func viewDidAppear(_ animated: Bool) {
        
        let centerViewHeight = centerView.bounds.height
        
        if centerView.bounds.height + 40 > contentView.bounds.height {
            
            NSLayoutConstraint.deactivate([self.contentViewHeight])
            self.contentViewHeight = NSLayoutConstraint(item: self.contentView, attribute: .height, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: centerViewHeight)
            NSLayoutConstraint.activate([self.contentViewHeight])
            self.centerViewCenterY.constant = 0
            self.view.layoutIfNeeded()
        }
    }
    
}
