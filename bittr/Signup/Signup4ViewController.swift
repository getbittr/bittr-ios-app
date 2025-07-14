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
    @IBOutlet weak var mnemonicField1: MnemonicTextField!
    @IBOutlet weak var mnemonicField2: MnemonicTextField!
    @IBOutlet weak var mnemonicField3: MnemonicTextField!
    @IBOutlet weak var label1: UILabel!
    @IBOutlet weak var label2: UILabel!
    @IBOutlet weak var label3: UILabel!
    
    @IBOutlet weak var scrollView: UIScrollView!
    @IBOutlet weak var contentView: UIView!
    @IBOutlet weak var contentViewBottom: NSLayoutConstraint!
    
    // Three checkable mnemonic words.
    var checkWords = [String]()
    var coreVC:CoreViewController?
    var signupVC:SignupViewController?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Corner radii
        self.mnemonicView1.layer.cornerRadius = 13
        self.mnemonicView2.layer.cornerRadius = 13
        self.mnemonicView3.layer.cornerRadius = 13
        self.saveView.layer.cornerRadius = 13
        
        // Button titles
        self.backButton.setTitle("", for: .normal)
        self.nextButton.setTitle("", for: .normal)
        self.backgroundButton.setTitle("", for: .normal)
        self.backgroundButton2.setTitle("", for: .normal)
        
        // Text field elements
        self.mnemonicField1.delegate = self
        self.mnemonicField2.delegate = self
        self.mnemonicField3.delegate = self
        
        // Configure MnemonicTextField properties
        self.mnemonicField1.tag = 1
        self.mnemonicField2.tag = 2
        self.mnemonicField3.tag = 3
        
        // Text field placeholders
        self.mnemonicField1.attributedPlaceholder = NSAttributedString(
            string: Language.getWord(withID: "enterword"),
            attributes: [NSAttributedString.Key.foregroundColor: UIColor.gray]
        )
        self.mnemonicField2.attributedPlaceholder = NSAttributedString(
            string: Language.getWord(withID: "enterword"),
            attributes: [NSAttributedString.Key.foregroundColor: UIColor.gray]
        )
        self.mnemonicField3.attributedPlaceholder = NSAttributedString(
            string: Language.getWord(withID: "enterword"),
            attributes: [NSAttributedString.Key.foregroundColor: UIColor.gray]
        )
        
        // Set colors and words
        self.changeColors()
        self.setWords()
        self.setMnemonic()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        
        // Set notification observers.
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillDisappear), name: UIResponder.keyboardWillHideNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillAppear), name: UIResponder.keyboardWillShowNotification, object: nil)
    }
    
    func setMnemonic() {
        
        if self.signupVC?.coreVC == nil { print("CoreVC nil in Signup4.") }
        if let actualMnemonic = self.signupVC?.coreVC?.newMnemonic {
            
            var indicesSet = Set<Int>()
            while indicesSet.count < 3 {
                indicesSet.insert(Int.random(in: 0...11))
            }
            var indicesToCheck:[Int] = Array(indicesSet)
            indicesToCheck.sort { int1, int2 in
                int1 < int2
            }
            
            self.label1.text = "\(indicesToCheck[0]+1)"
            self.label2.text = "\(indicesToCheck[1]+1)"
            self.label3.text = "\(indicesToCheck[2]+1)"
            
            self.checkWords = [actualMnemonic[indicesToCheck[0]], actualMnemonic[indicesToCheck[1]], actualMnemonic[indicesToCheck[2]]]
        }
    }
    
    @objc func keyboardWillDisappear() {
        
        NSLayoutConstraint.deactivate([self.contentViewBottom])
        self.contentViewBottom = NSLayoutConstraint(item: contentView!, attribute: .bottom, relatedBy: .equal, toItem: scrollView, attribute: .bottom, multiplier: 1, constant: 0)
        NSLayoutConstraint.activate([self.contentViewBottom])
        
        self.view.layoutIfNeeded()
    }
    
    @objc func keyboardWillAppear(_ notification:Notification) {
        
        if let keyboardSize = (notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue {
            
            let keyboardHeight = keyboardSize.height
            
            NSLayoutConstraint.deactivate([self.contentViewBottom])
            self.contentViewBottom = NSLayoutConstraint(item: contentView!, attribute: .bottom, relatedBy: .equal, toItem: scrollView, attribute: .bottom, multiplier: 1, constant: -keyboardHeight)
            NSLayoutConstraint.activate([self.contentViewBottom])
            
            self.view.layoutIfNeeded()
        }
    }
    
    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        
        // Update button state after a short delay to allow text to update
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.updateButtonState()
        }
        
        return true
    }
    
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        
        // Handle MnemonicTextField return key
        if let mnemonicField = textField as? MnemonicTextField {
            if mnemonicField.acceptSuggestionOnReturn() {
                // Suggestion was accepted, move to next field
                moveToNextField(from: textField)
                return false
            }
        }
        
        // No suggestion to accept, move to next field
        moveToNextField(from: textField)
        return false
    }
    
    func textFieldDidEndEditing(_ textField: UITextField) {
        // Check if this is the 3rd field and all fields are filled
        if textField.tag == 3 {
            let allFieldsHaveText = mnemonicField1.text?.trimmingCharacters(in: .whitespacesAndNewlines) == checkWords[0] && 
                                   mnemonicField2.text?.trimmingCharacters(in: .whitespacesAndNewlines) == checkWords[1] && 
                                   mnemonicField3.text?.trimmingCharacters(in: .whitespacesAndNewlines) == checkWords[2]
            
            if allFieldsHaveText {
                // Auto-trigger next button
                nextButtonTapped(nextButton)
            }
        }
    }
    
    func textFieldDidBeginEditing(_ textField: UITextField) {
        // Clear any existing suggestions when starting to edit
        if let mnemonicField = textField as? MnemonicTextField {
            mnemonicField.clearSuggestion()
        }
    }
    
    private func moveToNextField(from currentField: UITextField) {
        // Try to find the next field by tag
        if let nextField = currentField.superview?.superview?.viewWithTag(currentField.tag + 1) as? MnemonicTextField {
            _ = nextField.becomeFirstResponder()
        } else {
            // If no next field found, try to find it by looking at the text field order
            let textFields = [mnemonicField1, mnemonicField2, mnemonicField3]
            
            if let currentIndex = textFields.firstIndex(where: { $0 == currentField }),
               currentIndex + 1 < textFields.count {
                _ = textFields[currentIndex + 1]?.becomeFirstResponder()
            } else {
                currentField.resignFirstResponder()
            }
        }
    }
    
    private func updateButtonState() {
        // Make Next button clickable or unclickable.
        if self.mnemonicField1.text?.trimmingCharacters(in: .whitespacesAndNewlines) == self.checkWords[0] && self.mnemonicField2.text?.trimmingCharacters(in: .whitespacesAndNewlines) == self.checkWords[1] && self.mnemonicField3.text?.trimmingCharacters(in: .whitespacesAndNewlines) == self.checkWords[2] {
            self.saveView.backgroundColor = UIColor(red: 0, green: 0, blue: 0, alpha: 1)
        } else {
            self.saveView.backgroundColor = UIColor(red: 0, green: 0, blue: 0, alpha: 0.6)
        }
    }
    
    @IBAction func nextButtonTapped(_ sender: UIButton) {
        
        self.view.endEditing(true)
        
        // Validate that all fields are filled
        let field1Text = self.mnemonicField1.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let field2Text = self.mnemonicField2.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let field3Text = self.mnemonicField3.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        
        // Check for empty fields
        if field1Text.isEmpty || field2Text.isEmpty || field3Text.isEmpty {
            self.showAlert(
                presentingController: self,
                title: "Missing Words",
                message: "Please enter all 3 words to confirm your recovery phrase. This helps ensure you have backed up your wallet correctly.",
                buttons: ["OK"],
                actions: nil
            )
            return
        }
        
        // Validate that all words are from the recovery phrase word list
        var invalidWordMessages: [String] = []
        
        if !MnemonicWordListEN.contains(field1Text.lowercased()) {
            invalidWordMessages.append("Word 1: '\(field1Text)' is not a valid recovery phrase word")
        }
        if !MnemonicWordListEN.contains(field2Text.lowercased()) {
            invalidWordMessages.append("Word 2: '\(field2Text)' is not a valid recovery phrase word")
        }
        if !MnemonicWordListEN.contains(field3Text.lowercased()) {
            invalidWordMessages.append("Word 3: '\(field3Text)' is not a valid recovery phrase word")
        }
        
        if !invalidWordMessages.isEmpty {
            self.showAlert(
                presentingController: self,
                title: "Invalid Words",
                message: "Some of the words you entered are not valid recovery phrase words. Please check your backup and try again.",
                buttons: ["OK"],
                actions: nil
            )
            return
        }
        
        // Check if the words match the expected words
        if field1Text.lowercased() == self.checkWords[0].lowercased() && 
           field2Text.lowercased() == self.checkWords[1].lowercased() && 
           field3Text.lowercased() == self.checkWords[2].lowercased() {
            
            self.saveView.backgroundColor = UIColor(red: 0, green: 0, blue: 0, alpha: 1)
            self.signupVC?.moveToPage(7)
        } else {
            // Show friendly error message without revealing correct words
            self.showAlert(
                presentingController: self,
                title: "Incorrect Recovery Phrase",
                message: "Some of the words you entered are incorrect. Please double-check your recovery phrase backup and try again.\n\nFor your security, we recommend taking a fresh backup of your recovery phrase to ensure you have the correct words.",
                buttons: ["OK"],
                actions: nil
            )
        }
    }
    
    @IBAction func backButtonTapped(_ sender: UIButton) {
        
        self.view.endEditing(true)
        
        self.signupVC?.moveToPage(5)
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
