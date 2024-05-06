//
//  Restore2ViewController.swift
//  bittr
//
//  Created by Tom Melters on 29/08/2023.
//

import UIKit

class Restore2ViewController: UIViewController, UITextFieldDelegate {

    @IBOutlet weak var pinTextField: UITextField!
    @IBOutlet weak var nextButton: UIButton!
    @IBOutlet weak var saveView: UIView!
    
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
    
    @IBOutlet weak var contentView: UIView!
    @IBOutlet weak var centerView: UIView!
    @IBOutlet weak var contentViewHeight: NSLayoutConstraint!
    @IBOutlet weak var centerViewCenterY: NSLayoutConstraint!
    
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
        
        saveView.layer.cornerRadius = 13
        
        pinTextField.delegate = self
    }
    
    @IBAction func numberButtonTapped(_ sender: UIButton) {
        
        pinTextField.insertText(String(sender.tag))
        
        if pinTextField.text?.count ?? 0 > 3 {
            self.saveView.backgroundColor = UIColor(red: 0, green: 0, blue: 0, alpha: 1)
        } else {
            self.saveView.backgroundColor = UIColor(red: 0, green: 0, blue: 0, alpha: 0.6)
        }
    }
    
    @IBAction func backspaceButtonTapped(_ sender: UIButton) {
        
        pinTextField.deleteBackward()
        
        if pinTextField.text?.count ?? 0 > 3 {
            self.saveView.backgroundColor = UIColor(red: 0, green: 0, blue: 0, alpha: 1)
        } else {
            self.saveView.backgroundColor = UIColor(red: 0, green: 0, blue: 0, alpha: 0.6)
        }
    }
    
    func nextButtonTapped(enteredPin:String) {
        
        if enteredPin.count > 3 {
            let notificationDict:[String: Any] = ["page":"-4"]
            NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "signupnext"), object: nil, userInfo: notificationDict) as Notification)
            
            let pinNotificationDict:[String: Any] = ["previouspin":enteredPin]
            NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "previouspin"), object: nil, userInfo: pinNotificationDict) as Notification)
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
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        
        if segue.identifier == "Restore2ToPin" {
            if let actualPinVC = segue.destination as? PinViewController {
                actualPinVC.embeddingView = "restore2"
                actualPinVC.upperViewController = self
            }
        }
    }
    
}
