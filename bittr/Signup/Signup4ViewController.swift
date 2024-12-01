//
//  Signup4ViewController.swift
//  bittr
//
//  Created by Tom Melters on 01/06/2023.
//

import UIKit

class Signup4ViewController: UIViewController, UITextFieldDelegate {
    
    // View to double check that the user has properly recorded their mnemonic.
    
    @IBOutlet weak var topLabel: UILabel!
    
    @IBOutlet weak var mnemonicView1: UIView!
    @IBOutlet weak var mnemonicView2: UIView!
    @IBOutlet weak var mnemonicView3: UIView!
    @IBOutlet weak var saveView: UIView!
    @IBOutlet weak var nextButton: UIButton!
    @IBOutlet weak var nextLabel: UILabel!
    @IBOutlet weak var backLabel: UILabel!
    @IBOutlet weak var backButton: UIButton!
    @IBOutlet weak var backgroundButton: UIButton!
    @IBOutlet weak var backgroundButton2: UIButton!
    
    // Mnemonic text fields.
    @IBOutlet weak var mnemonicField1: UITextField!
    @IBOutlet weak var mnemonicField2: UITextField!
    @IBOutlet weak var mnemonicField3: UITextField!
    
    @IBOutlet weak var scrollView: UIScrollView!
    @IBOutlet weak var contentView: UIView!
    @IBOutlet weak var contentViewBottom: NSLayoutConstraint!
    
    // Three checkable mnemonic words.
    var checkWords = [String]()
    var coreVC:CoreViewController?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Corner radii and button titles.
        mnemonicView1.layer.cornerRadius = 13
        mnemonicView2.layer.cornerRadius = 13
        mnemonicView3.layer.cornerRadius = 13
        saveView.layer.cornerRadius = 13
        backButton.setTitle("", for: .normal)
        nextButton.setTitle("", for: .normal)
        backgroundButton.setTitle("", for: .normal)
        backgroundButton2.setTitle("", for: .normal)
        
        // Text field elements.
        mnemonicField1.delegate = self
        mnemonicField2.delegate = self
        mnemonicField3.delegate = self
        
        mnemonicField1.attributedPlaceholder = NSAttributedString(
            string: Language.getWord(withID: "enterword"),
            attributes: [NSAttributedString.Key.foregroundColor: UIColor.gray]
        )
        mnemonicField2.attributedPlaceholder = NSAttributedString(
            string: Language.getWord(withID: "enterword"),
            attributes: [NSAttributedString.Key.foregroundColor: UIColor.gray]
        )
        mnemonicField3.attributedPlaceholder = NSAttributedString(
            string: Language.getWord(withID: "enterword"),
            attributes: [NSAttributedString.Key.foregroundColor: UIColor.gray]
        )
        
        self.changeColors()
        self.setWords()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        
        // Set notification observers.
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillDisappear), name: UIResponder.keyboardWillHideNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillAppear), name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(setCheckWords), name: NSNotification.Name(rawValue: "setcheckwords"), object: nil)
    }
    
    @objc func setCheckWords(notification:NSNotification) {
        
        if let userInfo = notification.userInfo as [AnyHashable:Any]? {
            if let actualWords = userInfo["words"] as? [String] {
                self.checkWords = actualWords
            }
        }
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
    
    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        
        // Make Next button clickable or unclickable.
        if mnemonicField1.text?.trimmingCharacters(in: .whitespacesAndNewlines) == self.checkWords[0] && mnemonicField2.text?.trimmingCharacters(in: .whitespacesAndNewlines) == self.checkWords[1] && mnemonicField3.text?.trimmingCharacters(in: .whitespacesAndNewlines) == self.checkWords[2] {
            self.saveView.backgroundColor = UIColor(red: 0, green: 0, blue: 0, alpha: 1)
        } else {
            self.saveView.backgroundColor = UIColor(red: 0, green: 0, blue: 0, alpha: 0.6)
        }
        
        return true
    }
    
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        
        if let nextField = textField.superview?.superview?.viewWithTag(textField.tag + 1) as? UITextField {
            nextField.becomeFirstResponder()
        } else {
            textField.resignFirstResponder()
        }
        
        if mnemonicField1.text?.trimmingCharacters(in: .whitespacesAndNewlines) == self.checkWords[0] && mnemonicField2.text?.trimmingCharacters(in: .whitespacesAndNewlines) == self.checkWords[1] && mnemonicField3.text?.trimmingCharacters(in: .whitespacesAndNewlines) == self.checkWords[2] {
            self.saveView.backgroundColor = UIColor(red: 0, green: 0, blue: 0, alpha: 1)
        } else {
            self.saveView.backgroundColor = UIColor(red: 0, green: 0, blue: 0, alpha: 0.6)
        }
        
        return false
    }
    
    func textFieldDidEndEditing(_ textField: UITextField) {
        
        if mnemonicField1.text?.trimmingCharacters(in: .whitespacesAndNewlines) == self.checkWords[0] && mnemonicField2.text?.trimmingCharacters(in: .whitespacesAndNewlines) == self.checkWords[1] && mnemonicField3.text?.trimmingCharacters(in: .whitespacesAndNewlines) == self.checkWords[2] {
            self.saveView.backgroundColor = UIColor(red: 0, green: 0, blue: 0, alpha: 1)
        } else {
            self.saveView.backgroundColor = UIColor(red: 0, green: 0, blue: 0, alpha: 0.6)
        }
    }
    
    @IBAction func nextButtonTapped(_ sender: UIButton) {
        
        self.view.endEditing(true)
        
        if mnemonicField1.text?.trimmingCharacters(in: .whitespacesAndNewlines) == self.checkWords[0] && mnemonicField2.text?.trimmingCharacters(in: .whitespacesAndNewlines) == self.checkWords[1] && mnemonicField3.text?.trimmingCharacters(in: .whitespacesAndNewlines) == self.checkWords[2] {
            self.saveView.backgroundColor = UIColor(red: 0, green: 0, blue: 0, alpha: 1)
            
            let notificationDict:[String: Any] = ["page":sender.accessibilityIdentifier]
             NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "signupnext"), object: nil, userInfo: notificationDict) as Notification)
        }
    }
    
    @IBAction func backButtonTapped(_ sender: UIButton) {
        
        self.view.endEditing(true)
        
        let notificationDict:[String: Any] = ["page":sender.accessibilityIdentifier]
         NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "signupnext"), object: nil, userInfo: notificationDict) as Notification)
    }
    
    @IBAction func backgroundButtonTapped(_ sender: UIButton) {
        
        self.view.endEditing(true)
    }
    
    func changeColors() {
        self.topLabel.textColor = Colors.getColor("blackorwhite")
        if CacheManager.darkModeIsOn() {
            self.backLabel.textColor = Colors.getColor("blackorwhite")
        } else {
            self.backLabel.textColor = Colors.getColor("transparentblack")
        }
    }
    
    func setWords() {
        
        self.topLabel.text = Language.getWord(withID: "confirmrecoveryphrase")
        self.mnemonicField1.placeholder = Language.getWord(withID: "enterword")
        self.mnemonicField2.placeholder = Language.getWord(withID: "enterword")
        self.mnemonicField3.placeholder = Language.getWord(withID: "enterword")
        self.nextLabel.text = Language.getWord(withID: "confirm")
        self.backLabel.text = Language.getWord(withID: "back")
    }
    
}
