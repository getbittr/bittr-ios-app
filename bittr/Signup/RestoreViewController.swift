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
    var signupVC:SignupViewController?
    
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
        
        self.setTextFields(theseFields: [self.mnemonic1, self.mnemonic2, self.mnemonic3, self.mnemonic4, self.mnemonic5, self.mnemonic6, self.mnemonic7, self.mnemonic8, self.mnemonic9, self.mnemonic10, self.mnemonic11, self.mnemonic12])
        
        // Notification observers.
        //NotificationCenter.default.addObserver(self, selector: #selector(setSignupArticles), name: NSNotification.Name(rawValue: "setsignuparticles"), object: nil)
        //NotificationCenter.default.addObserver(self, selector: #selector(setArticleImage), name: NSNotification.Name(rawValue: "setimage\(pageArticle1Slug)"), object: nil)
        
        self.changeColors()
        self.setWords()
        self.getSignupArticle()
    }
    
    func getSignupArticle() {
        
        Task {
            await self.getArticle(self.pageArticle1Slug, coreVC: self.signupVC!.coreVC!) { result in
                
                switch result {
                case .success(let receivedArticle):
                    DispatchQueue.main.async {
                        self.pageArticle1 = receivedArticle
                        self.articleTitle.text = self.pageArticle1.title
                        self.articleButton.accessibilityIdentifier = self.pageArticle1Slug
                        self.articleImage.setArticleImage(url: self.pageArticle1.image, coreVC: self.signupVC?.coreVC, imageSpinner: self.spinner1)
                    }
                case .failure(let receivedError):
                    print("Couldn't get article: \(receivedError)")
                }
            }
        }
    }
    
    func setTextFields(theseFields:[UITextField]) {
        for eachField in theseFields {
            eachField.attributedPlaceholder = NSAttributedString(
                string: Language.getWord(withID: "enterword"),
                attributes: [NSAttributedString.Key.foregroundColor: UIColor.gray]
            )
        }
    }
    
    /*@objc func setSignupArticles(notification:NSNotification) {
        
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
    }*/
    
    override func viewWillAppear(_ animated: Bool) {
        
        if self.signupVC?.coreVC != nil {
            //self.signupVC!.coreVC!.infoVC?.getArticles()
            if self.signupVC!.coreVC!.resettingPin {
                self.restoreButtonText.text = Language.getWord(withID: "resetpin")
            }
        }
        
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillDisappear), name: UIResponder.keyboardWillHideNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillAppear), name: UIResponder.keyboardWillShowNotification, object: nil)
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
                if actualWord == "" {
                    self.restoreButtonSpinner.stopAnimating()
                    self.restoreButtonText.alpha = 1
                    return
                } else if enteredMnemonic == "" {
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
                                    self.signupVC?.moveToPage(1)
                                    
                                    /*let notificationDict:[String: Any] = ["page":sender.accessibilityIdentifier]
                                    NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "signupnext"), object: nil, userInfo: notificationDict) as Notification)*/
                                } else {
                                    // Entered mnemonic is incorrect.
                                    self.showAlert(presentingController: self, title: Language.getWord(withID: "forgotpin"), message: Language.getWord(withID: "forgotpin3"), buttons: [Language.getWord(withID: "okay")], actions: nil)
                                }
                            } else {
                                // No existing mnenonic is available.
                                self.showAlert(presentingController: self, title: Language.getWord(withID: "forgotpin"), message: "\(Language.getWord(withID: "forgotpin3")) 2", buttons: [Language.getWord(withID: "okay")], actions: nil)
                            }
                        } else {
                            // We're restoring an existing wallet.
                            // Store restorable mnemonic in cache.
                            CacheManager.storeMnemonic(mnemonic: enteredMnemonic)
                            
                            // Start wallet.
                            self.coreVC!.startLightning()
                            
                            // Proceed to next page.
                            self.signupVC?.moveToPage(1)
                            
                            /*let notificationDict:[String: Any] = ["page":sender.accessibilityIdentifier]
                            NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "signupnext"), object: nil, userInfo: notificationDict) as Notification)*/
                            
                            self.restoreButtonSpinner.stopAnimating()
                            self.restoreButtonText.alpha = 1
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
            
            /*let notificationDict:[String: Any] = ["page":sender.accessibilityIdentifier]
            NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "signupnext"), object: nil, userInfo: notificationDict) as Notification)*/
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
