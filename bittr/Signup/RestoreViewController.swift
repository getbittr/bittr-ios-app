//
//  RestoreViewController.swift
//  bittr
//
//  Created by Tom Melters on 11/06/2023.
//

import UIKit
import LDKNode
import LDKNodeFFI

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
    
    // Articles
    @IBOutlet weak var spinner1: UIActivityIndicatorView!
    @IBOutlet weak var articleImage: UIImageView!
    @IBOutlet weak var articleTitle: UILabel!
    let pageArticle1Slug = "wallet-recovery"
    var pageArticle1 = Article()
    
    @IBOutlet weak var restoreButtonText: UILabel!
    @IBOutlet weak var restoreButtonSpinner: UIActivityIndicatorView!
    
    var coreVC:CoreViewController?
    
    override func viewDidLoad() {
        super.viewDidLoad()

        // Corner radii and button titles.
        mnemonicView.layer.cornerRadius = 13
        restoreView.layer.cornerRadius = 13
        cardView.layer.cornerRadius = 13
        imageContainer.layer.cornerRadius = 13
        restoreButton.setTitle("", for: .normal)
        backgroundButton.setTitle("", for: .normal)
        backgroundButton2.setTitle("", for: .normal)
        backButton.setTitle("", for: .normal)
        articleButton.setTitle("", for: .normal)
        
        // Text fields.
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
        
        self.setTextFields(theseFields: [mnemonic1, mnemonic2, mnemonic3, mnemonic4, mnemonic5, mnemonic6, mnemonic7, mnemonic8, mnemonic9, mnemonic10, mnemonic11, mnemonic12])
        
        // Notification observers.
        NotificationCenter.default.addObserver(self, selector: #selector(setSignupArticles), name: NSNotification.Name(rawValue: "setsignuparticles"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(setArticleImage), name: NSNotification.Name(rawValue: "setimage\(pageArticle1Slug)"), object: nil)
        
        self.changeColors()
        self.setWords()
    }
    
    func setTextFields(theseFields:[UITextField]) {
        for eachField in theseFields {
            eachField.attributedPlaceholder = NSAttributedString(
                string: Language.getWord(withID: "enterword"),
                attributes: [NSAttributedString.Key.foregroundColor: UIColor.gray]
            )
        }
    }
    
    @objc func setSignupArticles(notification:NSNotification) {
        
        if let userInfo = notification.userInfo as [AnyHashable:Any]? {
            if let actualArticle = userInfo[pageArticle1Slug] as? Article {
                self.pageArticle1 = actualArticle
                DispatchQueue.main.async {
                    self.articleTitle.text = self.pageArticle1.title
                    if let actualData = CacheManager.getImage(key: self.pageArticle1.image) {
                        self.articleImage.image = UIImage(data: actualData)
                    }
                    if self.articleImage.image != nil {
                        self.spinner1.stopAnimating()
                    }
                }
                self.articleButton.accessibilityIdentifier = self.pageArticle1Slug
            }
        }
    }
    
    @objc func setArticleImage(notification:NSNotification) {
        
        if let userInfo = notification.userInfo as [AnyHashable:Any]? {
            if let actualImage = userInfo["image"] as? UIImage {
                self.spinner1.stopAnimating()
                self.articleImage.image = actualImage
            }
        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        
        if self.coreVC != nil {
            self.coreVC!.infoVC?.getArticles()
            if self.coreVC!.resettingPin {
                self.restoreButtonText.text = Language.getWord(withID: "resetpin")
            }
        }
        
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
        
        self.restoreButtonText.alpha = 0
        self.restoreButtonSpinner.startAnimating()
        
        let enteredWords = [self.mnemonic1.text, self.mnemonic2.text, self.mnemonic3.text, self.mnemonic4.text, self.mnemonic5.text, self.mnemonic6.text, self.mnemonic7.text, self.mnemonic8.text, self.mnemonic9.text, self.mnemonic10.text, self.mnemonic11.text, self.mnemonic12.text]
        
        var enteredMnemonic = ""
        var handledWords = 0
        
        for eachWord in enteredWords {
            if let actualWord = eachWord?.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: " ", with: "") as? String {
                if enteredMnemonic == "" {
                    enteredMnemonic = actualWord
                    handledWords += 1
                } else {
                    enteredMnemonic = "\(enteredMnemonic) \(actualWord)"
                    handledWords += 1
                    if handledWords == 12 {
                        
                        if self.coreVC == nil {
                            return
                        } else if self.coreVC!.resettingPin {
                            // We're resetting the device PIN.
                            
                            self.restoreButtonSpinner.stopAnimating()
                            self.restoreButtonText.alpha = 1
                            
                            if let currentMnemonic = CacheManager.getMnemonic() {
                                if currentMnemonic == enteredMnemonic {
                                    // Correct mnemonic has been entered.
                                    
                                    // Start wallet.
                                    self.coreVC!.startLightning()
                                    
                                    // Proceed to next page.
                                    let notificationDict:[String: Any] = ["page":sender.accessibilityIdentifier]
                                    NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "signupnext"), object: nil, userInfo: notificationDict) as Notification)
                                } else {
                                    // Entered mnemonic is incorrect.
                                    self.showAlert(title: Language.getWord(withID: "forgotpin"), message: Language.getWord(withID: "forgotpin3"), buttons: [Language.getWord(withID: "okay")], actions: nil)
                                }
                            } else {
                                // No existing mnenonic is available.
                                self.showAlert(title: Language.getWord(withID: "forgotpin"), message: "\(Language.getWord(withID: "forgotpin3")) 2", buttons: [Language.getWord(withID: "okay")], actions: nil)
                            }
                        } else {
                            // We're restoring an existing wallet.
                            // Store restorable mnemonic in cache.
                            CacheManager.storeMnemonic(mnemonic: enteredMnemonic)
                            
                            // Start wallet.
                            self.coreVC!.startLightning()
                            
                            // Proceed to next page.
                            let notificationDict:[String: Any] = ["page":sender.accessibilityIdentifier]
                            NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "signupnext"), object: nil, userInfo: notificationDict) as Notification)
                            
                            self.restoreButtonSpinner.stopAnimating()
                            self.restoreButtonText.alpha = 1
                        }
                    }
                }
            }
        }
    }
    
    @IBAction func backButtonTapped(_ sender: UIButton) {
        
        self.view.endEditing(true)
        
        if self.coreVC == nil {
            return
        } else if self.coreVC!.resettingPin {
            // We're resetting the device PIN.
            self.coreVC!.pinContainerView.alpha = 1
            self.coreVC!.resettingPin = false
            self.coreVC!.hideSignup()
        } else {
            // We're restoring an existing wallet.
            let notificationDict:[String: Any] = ["page":sender.accessibilityIdentifier]
            NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "signupnext"), object: nil, userInfo: notificationDict) as Notification)
        }
    }
    
    @IBAction func backgroundButtonTapped(_ sender: UIButton) {
        self.view.endEditing(true)
    }
    
    @IBAction func articleButtonTapped(_ sender: UIButton) {
        
        let notificationDict:[String: Any] = ["tag":sender.accessibilityIdentifier]
        
        NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "launcharticle"), object: nil, userInfo: notificationDict) as Notification)
    }
    
    func changeColors() {
        
        self.topLabel.textColor = Colors.getColor("blackorwhite")
        
        if CacheManager.darkModeIsOn() {
            self.cancelLabel.textColor = Colors.getColor("blackorwhite")
        } else {
            self.cancelLabel.textColor = Colors.getColor("transparentblack")
        }

    }
    
    func setWords() {
        
        self.topLabel.text = Language.getWord(withID: "enterrecoveryphrase")
        self.restoreButtonText.text = Language.getWord(withID: "restorewallet")
        self.cancelLabel.text = Language.getWord(withID: "cancel")
    }
    
}
