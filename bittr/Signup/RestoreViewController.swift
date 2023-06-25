//
//  RestoreViewController.swift
//  bittr
//
//  Created by Tom Melters on 11/06/2023.
//

import UIKit

class RestoreViewController: UIViewController, UITextFieldDelegate {

    @IBOutlet weak var mnemonicView: UIView!
    @IBOutlet weak var restoreView: UIView!
    @IBOutlet weak var restoreButton: UIButton!
    @IBOutlet weak var cardView: UIView!
    @IBOutlet weak var imageContainer: UIView!
    @IBOutlet weak var articleButton: UIButton!
    
    @IBOutlet weak var mnemonic1: UITextField!
    @IBOutlet weak var mnemonic2: UITextField!
    @IBOutlet weak var mnemonic3: UITextField!
    @IBOutlet weak var mnemonic4: UITextField!
    @IBOutlet weak var mnemonic5: UITextField!
    @IBOutlet weak var mnemonic6: UITextField!
    @IBOutlet weak var mnemonic7: UITextField!
    @IBOutlet weak var mnemonic8: UITextField!
    @IBOutlet weak var mnemonic9: UITextField!
    @IBOutlet weak var mnemonic10: UITextField!
    @IBOutlet weak var mnemonic11: UITextField!
    @IBOutlet weak var mnemonic12: UITextField!
    
    @IBOutlet weak var scrollView: UIScrollView!
    @IBOutlet weak var contentView: UIView!
    @IBOutlet weak var contentViewBottom: NSLayoutConstraint!
    
    @IBOutlet weak var backgroundButton: UIButton!
    @IBOutlet weak var backgroundButton2: UIButton!
    @IBOutlet weak var backButton: UIButton!
    
    override func viewDidLoad() {
        super.viewDidLoad()

        mnemonicView.layer.cornerRadius = 13
        restoreView.layer.cornerRadius = 13
        cardView.layer.cornerRadius = 13
        imageContainer.layer.cornerRadius = 13
        
        restoreButton.setTitle("", for: .normal)
        backgroundButton.setTitle("", for: .normal)
        backgroundButton2.setTitle("", for: .normal)
        backButton.setTitle("", for: .normal)
        articleButton.setTitle("", for: .normal)
        
        mnemonic1.delegate = self
        mnemonic2.delegate = self
        mnemonic3.delegate = self
        mnemonic4.delegate = self
        mnemonic5.delegate = self
        mnemonic6.delegate = self
        mnemonic7.delegate = self
        mnemonic8.delegate = self
        mnemonic9.delegate = self
        mnemonic10.delegate = self
        mnemonic11.delegate = self
        mnemonic12.delegate = self
    }
    
    override func viewWillAppear(_ animated: Bool) {
        
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillDisappear), name: UIResponder.keyboardWillHideNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillAppear), name: UIResponder.keyboardWillShowNotification, object: nil)
    }
    
    @objc func keyboardWillDisappear() {
        
        NSLayoutConstraint.deactivate([contentViewBottom])
        contentViewBottom = NSLayoutConstraint(item: contentView!, attribute: .bottom, relatedBy: .equal, toItem: scrollView, attribute: .bottom, multiplier: 1, constant: 0)
        NSLayoutConstraint.activate([contentViewBottom])
        
        self.view.layoutIfNeeded()
    }
    
    @objc func keyboardWillAppear(_ notification:Notification) {
        
        if let keyboardSize = (notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue {
            
            let keyboardHeight = keyboardSize.height
            
            NSLayoutConstraint.deactivate([contentViewBottom])
            contentViewBottom = NSLayoutConstraint(item: contentView!, attribute: .bottom, relatedBy: .equal, toItem: scrollView, attribute: .bottom, multiplier: 1, constant: -keyboardHeight)
            NSLayoutConstraint.activate([contentViewBottom])
            
            self.view.layoutIfNeeded()
        }
    }
    
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        
        if let nextField = textField.superview?.superview?.superview?.viewWithTag(textField.tag + 1) as? UITextField {
            nextField.becomeFirstResponder()
        } else {
            textField.resignFirstResponder()
        }
        
        return false
    }
    
    @IBAction func restoreButtonTapped(_ sender: UIButton) {
        
        self.view.endEditing(true)
        
        NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "restorewallet"), object: nil, userInfo: nil) as Notification)
    }
    
    @IBAction func backButtonTapped(_ sender: UIButton) {
        
        let notificationDict:[String: Any] = ["page":sender.accessibilityIdentifier]
         NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "signupnext"), object: nil, userInfo: notificationDict) as Notification)
    }
    
    @IBAction func backgroundButtonTapped(_ sender: UIButton) {
        self.view.endEditing(true)
    }
    
    @IBAction func articleButtonTapped(_ sender: UIButton) {
        
        let notificationDict:[String: Any] = ["tag":sender.tag]
        
        NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "launcharticle"), object: nil, userInfo: notificationDict) as Notification)
    }
    
}
