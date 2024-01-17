//
//  RestoreViewController.swift
//  bittr
//
//  Created by Tom Melters on 11/06/2023.
//

import UIKit
import KeychainSwift
import LDKNode

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
    
    @IBOutlet weak var spinner1: UIActivityIndicatorView!
    @IBOutlet weak var articleImage: UIImageView!
    @IBOutlet weak var articleTitle: UILabel!
    let pageArticle1Slug = "wallet-recovery"
    var pageArticle1 = Article()
    
    @IBOutlet weak var restoreButtonText: UILabel!
    @IBOutlet weak var restoreButtonSpinner: UIActivityIndicatorView!
    
    let keychain = KeychainSwift()
    
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
        
        NotificationCenter.default.addObserver(self, selector: #selector(setSignupArticles), name: NSNotification.Name(rawValue: "setsignuparticles"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(setArticleImage), name: NSNotification.Name(rawValue: "setimage\(pageArticle1Slug)"), object: nil)
    }
    
    @objc func setSignupArticles(notification:NSNotification) {
        
        if let userInfo = notification.userInfo as [AnyHashable:Any]? {
            if let actualArticle = userInfo[pageArticle1Slug] as? Article {
                self.pageArticle1 = actualArticle
                DispatchQueue.main.async {
                    self.articleTitle.text = self.pageArticle1.title
                    self.articleImage.image = UIImage(data: CacheManager.getImage(key: self.pageArticle1.image))
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
        
        for eachWord in enteredWords {
            if let actualWord = eachWord?.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: " ", with: "") as? String {
                if enteredMnemonic == "" {
                    enteredMnemonic = actualWord
                } else {
                    enteredMnemonic = "\(enteredMnemonic) \(actualWord)"
                }
            } else {
                
            }
        }
        
        /*let defaults = UserDefaults.standard
        defaults.set(enteredMnemonic, forKey: "newmnemonic")
        defaults.synchronize()*/
        
        if keychain.get("") != nil {
            UserDefaults.standard.set(true, forKey: "deletestorage")
        }
        if CacheManager.getMnemonic() != "empty" {
            UserDefaults.standard.set(true, forKey: "deletestorage")
        }
        
        CacheManager.storeMnemonic(mnemonic: enteredMnemonic)
        /*keychain.synchronizable = true
        keychain.set(enteredMnemonic, forKey: "")*/
        
        do {
            try FileManager.default.removeItem(atPath: LightningStorage().getDocumentsDirectory())
        } catch {
            print(error.localizedDescription)
        }
        
        
        Task {
            do {
                try await LightningNodeService.shared.start()
            } catch let error as NodeError {
                print(error.localizedDescription)
            } catch {
                print(error.localizedDescription)
            }
        }
        
        
        //LightningNodeService.init(network: LDKNode.Network.testnet)
        /*Task {
            do {
                //try LightningNodeService.shared.stop()
                
                /*keychain.synchronizable = true
                keychain.set(enteredMnemonic, forKey: "")*/
                try await LightningNodeService.shared.start()
                
                /*do {
                    try await LightningNodeService.shared.start()
                    LightningNodeService.init(network: LDKNode.Network.testnet)
                } catch let error as NodeError {
                    print(error.localizedDescription)
                } catch {
                    print(error.localizedDescription)
                }*/
            } catch let error as NodeError {
                print(error.localizedDescription)
            } catch {
                print(error.localizedDescription)
            }
        }*/
        
        let notificationDict:[String: Any] = ["page":sender.accessibilityIdentifier]
        NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "signupnext"), object: nil, userInfo: notificationDict) as Notification)
        
        self.restoreButtonSpinner.stopAnimating()
        self.restoreButtonText.alpha = 1
    }
    
    @IBAction func backButtonTapped(_ sender: UIButton) {
        
        self.view.endEditing(true)
        
        let notificationDict:[String: Any] = ["page":sender.accessibilityIdentifier]
         NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "signupnext"), object: nil, userInfo: notificationDict) as Notification)
    }
    
    @IBAction func backgroundButtonTapped(_ sender: UIButton) {
        self.view.endEditing(true)
    }
    
    @IBAction func articleButtonTapped(_ sender: UIButton) {
        
        let notificationDict:[String: Any] = ["tag":sender.accessibilityIdentifier]
        
        NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "launcharticle"), object: nil, userInfo: notificationDict) as Notification)
    }
    
}
