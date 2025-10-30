//
//  RestoreViewController.swift
//  bittr
//
//  Created by Tom Melters on 11/06/2023.
//

import UIKit
import LDKNode
import LDKNodeFFI
import BitcoinDevKit
import Sentry

class RestoreViewController: UIViewController, UITextFieldDelegate {

    // Restore an existing wallet.
    
    // Views and buttons.
    @IBOutlet weak var topLabel: UILabel!
    @IBOutlet weak var mnemonicView: UIView!
    @IBOutlet weak var restoreView: UIView!
    @IBOutlet weak var restoreButton: UIButton!
    @IBOutlet weak var cancelLabel: UILabel!
    @IBOutlet weak var cardView: UIView!
    @IBOutlet weak var imageContainer: UIView!
    @IBOutlet weak var articleButton: UIButton!
    
    // Text fields.
    @IBOutlet weak var mnemonic1: MnemonicTextField!
    @IBOutlet weak var mnemonic2: MnemonicTextField!
    @IBOutlet weak var mnemonic3: MnemonicTextField!
    @IBOutlet weak var mnemonic4: MnemonicTextField!
    @IBOutlet weak var mnemonic5: MnemonicTextField!
    @IBOutlet weak var mnemonic6: MnemonicTextField!
    @IBOutlet weak var mnemonic7: MnemonicTextField!
    @IBOutlet weak var mnemonic8: MnemonicTextField!
    @IBOutlet weak var mnemonic9: MnemonicTextField!
    @IBOutlet weak var mnemonic10: MnemonicTextField!
    @IBOutlet weak var mnemonic11: MnemonicTextField!
    @IBOutlet weak var mnemonic12: MnemonicTextField!
    
    @IBOutlet weak var scrollView: UIScrollView!
    @IBOutlet weak var contentView: UIView!
    @IBOutlet weak var contentViewBottom: NSLayoutConstraint!
    
    @IBOutlet weak var backgroundButton: UIButton!
    @IBOutlet weak var backgroundButton2: UIButton!
    @IBOutlet weak var backButton: UIButton!
    
    // Articles
    @IBOutlet weak var spinner1: UIActivityIndicatorView!
    @IBOutlet weak var articleImage: UIImageView!
    @IBOutlet weak var articleTitle: UILabel!
    let pageArticle1Slug = "wallet-recovery"
    var pageArticle1 = Article()
    
    // Remove wallet
    @IBOutlet weak var removeWalletStack: UIView!
    @IBOutlet weak var removeWalletStackHeight: NSLayoutConstraint!
    @IBOutlet weak var removeWalletLabel: UILabel!
    @IBOutlet weak var removeWalletButton: UIButton!
    
    // Restore button
    @IBOutlet weak var restoreButtonText: UILabel!
    @IBOutlet weak var restoreButtonSpinner: UIActivityIndicatorView!
    
    var coreVC:CoreViewController?
    var signupVC:SignupViewController?
    
    // No longer needed with inline autocomplete
    
    override func viewDidLoad() {
        super.viewDidLoad()

        // Corner radii
        self.mnemonicView.layer.cornerRadius = 13
        self.restoreView.layer.cornerRadius = 13
        self.cardView.layer.cornerRadius = 13
        self.imageContainer.layer.cornerRadius = 13
        
        // Button titles
        self.restoreButton.setTitle("", for: .normal)
        self.backgroundButton.setTitle("", for: .normal)
        self.backgroundButton2.setTitle("", for: .normal)
        self.backButton.setTitle("", for: .normal)
        self.articleButton.setTitle("", for: .normal)
        self.removeWalletButton.setTitle("", for: .normal)
        
        // Text fields.
        self.mnemonic1.delegate = self
        self.mnemonic2.delegate = self
        self.mnemonic3.delegate = self
        self.mnemonic4.delegate = self
        self.mnemonic5.delegate = self
        self.mnemonic6.delegate = self
        self.mnemonic7.delegate = self
        self.mnemonic8.delegate = self
        self.mnemonic9.delegate = self
        self.mnemonic10.delegate = self
        self.mnemonic11.delegate = self
        self.mnemonic12.delegate = self
        
        // Configure MnemonicTextField properties
        let textFields = [self.mnemonic1, self.mnemonic2, self.mnemonic3, self.mnemonic4, self.mnemonic5, self.mnemonic6, 
                         self.mnemonic7, self.mnemonic8, self.mnemonic9, self.mnemonic10, self.mnemonic11, self.mnemonic12]
        
        for (index, textField) in textFields.enumerated() {
            textField?.tag = index + 1
            textField?.delegate = self
            textField?.attributedPlaceholder = NSAttributedString(
                string: Language.getWord(withID: "enterword"),
                attributes: [NSAttributedString.Key.foregroundColor: UIColor.gray]
            )
            textField?.returnKeyType = .next
        }
        
        if self.coreVC != nil, self.coreVC!.resettingPin {
            self.removeWalletStack.alpha = 1
            self.removeWalletStackHeight.constant = 45
            self.removeWalletLabel.alpha = 0.5
        } else {
            self.removeWalletStack.alpha = 0
            self.removeWalletStackHeight.constant = 0
        }
        
        self.changeColors()
        self.setWords()
        Task {
            await self.setSignupArticle(articleSlug: self.pageArticle1Slug, coreVC: self.signupVC!.coreVC!, articleButton: self.articleButton, articleTitle: self.articleTitle, articleImage: self.articleImage, articleSpinner: self.spinner1, completion: { article in
                self.pageArticle1 = article ?? Article()
            })
        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillDisappear), name: UIResponder.keyboardWillHideNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillAppear), name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(changeColors), name: NSNotification.Name(rawValue: "changecolors"), object: nil)
    }
    
    @objc func keyboardWillDisappear() {
        
        NSLayoutConstraint.deactivate([self.contentViewBottom])
        self.contentViewBottom = NSLayoutConstraint(item: self.contentView!, attribute: .bottom, relatedBy: .equal, toItem: self.scrollView, attribute: .bottom, multiplier: 1, constant: 0)
        NSLayoutConstraint.activate([self.contentViewBottom])
        
        self.view.layoutIfNeeded()
    }
    
    @objc func keyboardWillAppear(_ notification:Notification) {
        
        if let keyboardSize = (notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue {
            
            let keyboardHeight = keyboardSize.height
            
            NSLayoutConstraint.deactivate([self.contentViewBottom])
            self.contentViewBottom = NSLayoutConstraint(item: self.contentView!, attribute: .bottom, relatedBy: .equal, toItem: self.scrollView, attribute: .bottom, multiplier: 1, constant: -keyboardHeight)
            NSLayoutConstraint.activate([self.contentViewBottom])
            
            self.view.layoutIfNeeded()
        }
    }
    
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        
        // Check if this is a MnemonicTextField and handle suggestion acceptance
        if let mnemonicField = textField as? MnemonicTextField {
            if mnemonicField.acceptSuggestionOnReturn() {
                // Suggestion was accepted, move to next field
                moveToNextField(from: textField)
                return false
            }
        }
        
        // If this is the 12th field, trigger restore
        if textField.tag == 12 {
            restoreButtonTapped(restoreButton)
            return false
        }
        
        // No suggestion to accept, move to next field
        moveToNextField(from: textField)
        return false
    }
    
    private func moveToNextField(from currentField: UITextField) {
        // Try to find the next field by tag
        if let nextField = currentField.superview?.superview?.superview?.viewWithTag(currentField.tag + 1) as? UITextField {
            _ = nextField.becomeFirstResponder()
        } else {
            // If no next field found, try to find it by looking at the text field order
            let textFields = [mnemonic1, mnemonic2, mnemonic3, mnemonic4, mnemonic5, mnemonic6, 
                             mnemonic7, mnemonic8, mnemonic9, mnemonic10, mnemonic11, mnemonic12]
            
            if let currentIndex = textFields.firstIndex(where: { $0 == currentField }),
               currentIndex + 1 < textFields.count {
                _ = textFields[currentIndex + 1]?.becomeFirstResponder()
            } else {
                currentField.resignFirstResponder()
            }
        }
    }
    
    @IBAction func restoreButtonTapped(_ sender: UIButton) {
        
        self.view.endEditing(true)
        
        self.restoreButtonText.alpha = 0
        self.restoreButtonSpinner.startAnimating()
        
        let enteredWords = [self.mnemonic1.text, self.mnemonic2.text, self.mnemonic3.text, self.mnemonic4.text, self.mnemonic5.text, self.mnemonic6.text, self.mnemonic7.text, self.mnemonic8.text, self.mnemonic9.text, self.mnemonic10.text, self.mnemonic11.text, self.mnemonic12.text]
        
        print("Restore button tapped - checking words: \(enteredWords)")
        
        var enteredMnemonic = ""
        var handledWords = 0
        
        for eachWord in enteredWords {
            if let actualWord = eachWord?.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: " ", with: "") as? String {
                print("Processing word: '\(actualWord)'")
                if actualWord == "" {
                    // Found an empty field - show warning
                    print("Found empty field - showing warning")
                    self.restoreButtonSpinner.stopAnimating()
                    self.restoreButtonText.alpha = 1
                    self.showAlert(
                        presentingController: self.signupVC?.coreVC ?? self.signupVC ?? self,
                        title: Language.getWord(withID: "incompletephrase"),
                        message: Language.getWord(withID: "incompletephrase2"),
                        buttons: [Language.getWord(withID: "okay")],
                        actions: nil
                    )
                    return
                } else if enteredMnemonic == "" {
                    enteredMnemonic = actualWord
                    handledWords += 1
                    print("First word added: \(enteredMnemonic), handledWords: \(handledWords)")
                } else {
                    enteredMnemonic = "\(enteredMnemonic) \(actualWord)"
                    handledWords += 1
                    print("Word added: \(enteredMnemonic), handledWords: \(handledWords)")
                    if handledWords == 12 {
                        print("All 12 words collected: \(enteredMnemonic)")
                        print("About to check coreVC...")
                        
                        if self.coreVC == nil {
                            print("coreVC is nil - stopping spinner and showing error")
                            self.restoreButtonSpinner.stopAnimating()
                            self.restoreButtonText.alpha = 1
                            self.showAlert(
                                presentingController: self.signupVC?.coreVC ?? self.signupVC ?? self,
                                title: Language.getWord(withID: "error"),
                                message: Language.getWord(withID: "restorewalleterror"),
                                buttons: [Language.getWord(withID: "okay")],
                                actions: nil
                            )
                            return
                        } else if self.coreVC!.resettingPin {
                            print("PIN reset mode detected")
                            // We're resetting the device PIN.
                            
                            self.restoreButtonSpinner.stopAnimating()
                            self.restoreButtonText.alpha = 1
                            
                            if let currentMnemonic = CacheManager.getMnemonic() {
                                if currentMnemonic == enteredMnemonic {
                                    // Correct mnemonic has been entered.
                                    
                                    // Start wallet.
                                    self.coreVC!.startLightning()
                                    
                                    // Proceed to next page.
                                    self.signupVC?.moveToPage(1)
                                } else {
                                    // Entered mnemonic is incorrect.
                                    self.showAlert(presentingController: self.signupVC?.coreVC ?? self.signupVC ?? self, title: Language.getWord(withID: "forgotpin"), message: Language.getWord(withID: "forgotpin3"), buttons: [Language.getWord(withID: "okay")], actions: nil)
                                }
                            } else {
                                // No existing mnenonic is available.
                                self.showAlert(presentingController: self.signupVC?.coreVC ?? self.signupVC ?? self, title: Language.getWord(withID: "forgotpin"), message: "\(Language.getWord(withID: "forgotpin3")) 2", buttons: [Language.getWord(withID: "okay")], actions: nil)
                            }
                        } else {
                            print("Wallet restore mode detected")
                            // We're restoring an existing wallet.
                            
                            // Validate mnemonic using BitcoinDevKit before storing
                            do {
                                print("Validating mnemonic with BitcoinDevKit: \(enteredMnemonic)")
                                _ = try BitcoinDevKit.Mnemonic.fromString(mnemonic: enteredMnemonic)
                                print("Mnemonic validation successful")
                                
                                                                // Store restorable mnemonic in cache.
                                CacheManager.storeMnemonic(mnemonic: enteredMnemonic)
                                
                                print("About to start Lightning wallet...")
                                // Start wallet.
                                self.coreVC!.startLightning()
                                print("Lightning wallet started successfully")
                                
                                // Proceed to next page.
                                self.signupVC?.moveToPage(1)
                                print("Moved to next page")
                                
                                self.restoreButtonSpinner.stopAnimating()
                                self.restoreButtonText.alpha = 1
                                print("Restore process completed successfully")
                                
                            } catch {
                                print("Mnemonic validation failed: \(error)")
                                DispatchQueue.main.async {
                                    SentrySDK.capture(error: error) { scope in
                                        scope.setExtra(value: "RestoreViewController row 313", key: "context")
                                    }
                                    self.restoreButtonSpinner.stopAnimating()
                                    self.restoreButtonText.alpha = 1
                                    self.showAlert(
                                        presentingController: self.signupVC?.coreVC ?? self.signupVC ?? self,
                                        title: Language.getWord(withID: "invalidphrase"),
                                        message: Language.getWord(withID: "invalidphrase2"),
                                        buttons: [Language.getWord(withID: "okay")],
                                        actions: nil
                                    )
                                    return
                                }
                            }
                        }
                    }
                }
            } else {
                self.restoreButtonSpinner.stopAnimating()
                self.restoreButtonText.alpha = 1
                return
            }
        }
    }
    
    @IBAction func backButtonTapped(_ sender: UIButton) {
        
        self.view.endEditing(true)
        
        if self.signupVC == nil {
            return
        } else if self.signupVC!.coreVC == nil {
            return
        } else if self.signupVC!.coreVC!.resettingPin {
            // We're resetting the device PIN.
            self.signupVC!.coreVC!.pinContainerView.alpha = 1
            self.signupVC!.coreVC!.resettingPin = false
            self.signupVC!.coreVC!.hideSignup()
        } else {
            // We're restoring an existing wallet.
            self.signupVC!.moveToPage(3)
        }
    }
    
    @IBAction func removeWalletButtonTapped(_ sender: UIButton) {
        
        if self.coreVC != nil, self.coreVC!.settingsVC != nil {
            let restoreButton = UIButton()
            restoreButton.accessibilityIdentifier = "restore"
            self.coreVC!.settingsVC!.settingsTapped(restoreButton)
        }
    }
    
    @IBAction func backgroundButtonTapped(_ sender: UIButton) {
        self.view.endEditing(true)
    }
    
    @IBAction func articleButtonTapped(_ sender: UIButton) {
        if sender.accessibilityIdentifier != nil {
            self.coreVC!.launchArticle(articleTag: "\(sender.accessibilityIdentifier!)")
        }
    }
    
    @objc func changeColors() {
        
        self.topLabel.textColor = Colors.getColor("blackorwhite")
        self.cancelLabel.textColor = Colors.getColor("transparentblack")

    }
    
    func setWords() {
        
        self.topLabel.text = Language.getWord(withID: "enterrecoveryphrase")
        if self.coreVC != nil, self.coreVC!.resettingPin {
            self.restoreButtonText.text = Language.getWord(withID: "resetpin")
        } else {
            self.restoreButtonText.text = Language.getWord(withID: "restorewallet")
        }
        self.cancelLabel.text = Language.getWord(withID: "cancel")
        self.removeWalletLabel.text = Language.getWord(withID: "removewalletfromdevice")
    }
    
    // MARK: - UITextFieldDelegate
    
    func textFieldDidBeginEditing(_ textField: UITextField) {
        // Clear any existing suggestions when starting to edit
        if let mnemonicField = textField as? MnemonicTextField {
            mnemonicField.clearSuggestion()
        }
    }
    
    func textFieldDidEndEditing(_ textField: UITextField) {
        // Clear suggestions when done editing
        if let mnemonicField = textField as? MnemonicTextField {
            mnemonicField.clearSuggestion()
        }
    }
    

    
}
