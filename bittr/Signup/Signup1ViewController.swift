//
//  Signup1ViewController.swift
//  bittr
//
//  Created by Tom Melters on 22/05/2023.
//

import UIKit
import BitcoinDevKit

class Signup1ViewController: UIViewController {

    // Create or Restore wallet view. First view new users see.
    
    @IBOutlet weak var headerView: UIView!
    @IBOutlet weak var headerLabel: UILabel!
    @IBOutlet weak var topLabel: UILabel!
    
    // Next button
    @IBOutlet weak var buttonView: UIView!
    @IBOutlet weak var nextButton: UIButton!
    
    // Restore button
    @IBOutlet weak var restoreView: UIView!
    @IBOutlet weak var restoreButton: UIButton!
    @IBOutlet weak var restoreLabel: UILabel!
    
    // Article
    @IBOutlet weak var cardView: UIView!
    @IBOutlet weak var imageContainer: UIView!
    @IBOutlet weak var articleButton: UIButton!
    @IBOutlet weak var spinner1: UIActivityIndicatorView!
    @IBOutlet weak var articleImage: UIImageView!
    @IBOutlet weak var articleTitle: UILabel!
    let pageArticle1Slug = "what-is-bittr"
    var pageArticle1 = Article()
    
    @IBOutlet weak var nextButtonSpinner: UIActivityIndicatorView!
    @IBOutlet weak var createWalletLabel: UILabel!
    
    var nextTapped = false
    var coreVC:CoreViewController?
    
    override func viewDidLoad() {
        super.viewDidLoad()

        // Corner radii and button titles.
        headerView.layer.cornerRadius = 13
        buttonView.layer.cornerRadius = 13
        restoreView.layer.cornerRadius = 13
        cardView.layer.cornerRadius = 13
        imageContainer.layer.cornerRadius = 13
        nextButton.setTitle("", for: .normal)
        restoreButton.setTitle("", for: .normal)
        articleButton.setTitle("", for: .normal)
        
        cardView.layer.shadowColor = UIColor.black.cgColor
        cardView.layer.shadowOffset = CGSize(width: 0, height: 8)
        cardView.layer.shadowRadius = 12.0
        cardView.layer.shadowOpacity = 0.05
        
        NotificationCenter.default.addObserver(self, selector: #selector(setSignupArticles), name: NSNotification.Name(rawValue: "setsignuparticles"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(setArticleImage), name: NSNotification.Name(rawValue: "setimage\(pageArticle1Slug)"), object: nil)
        
        self.changeColors()
        self.setWords()
    }
    
    
    @objc func setSignupArticles(notification:NSNotification) {
        
        // Set article image.
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
    

    @IBAction func restoreButtonClicked(_ sender: UIButton) {
        
        // Check internet connection.
        if !Reachability.isConnectedToNetwork() {
            // User not connected to internet.
            self.showAlert(Language.getWord(withID: "checkyourconnection"), Language.getWord(withID: "trytoconnect"), Language.getWord(withID: "okay"))
            return
        }
        
        let notificationDict:[String: Any] = ["page":sender.accessibilityIdentifier]
        NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "signupnext"), object: nil, userInfo: notificationDict) as Notification)
    }
    
    @IBAction func nextButtonTapped(_ sender: UIButton) {
        
        // Check internet connection.
        if !Reachability.isConnectedToNetwork() {
            // User not connected to internet.
            self.showAlert(Language.getWord(withID: "checkyourconnection"), Language.getWord(withID: "trytoconnect"), Language.getWord(withID: "okay"))
            return
        }
        
        self.createWalletLabel.alpha = 0
        self.nextButtonSpinner.startAnimating()
        self.nextTapped = true
        
        var mnemonicString = ""
        if let actualMnemonic = CacheManager.getMnemonic() {
            // Mnemonic found in storage.
            print("Did find mnemonic.")
            mnemonicString = actualMnemonic
        } else {
            // Create new mnemonic.
            print("Did not find mnemonic. Creating a new one.")
            let mnemonic = BitcoinDevKit.Mnemonic.init(wordCount: .words12)
            mnemonicString = mnemonic.asString()
            CacheManager.storeMnemonic(mnemonic: mnemonicString)
        }
        
        // Send mnemonic to 3rd signup view.
        if self.coreVC == nil { print("CoreVC nil.") }
        self.coreVC?.newMnemonic = mnemonicString.components(separatedBy: " ")
        NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "setwords"), object: nil, userInfo: nil) as Notification)
        
        self.didReceiveMnemonic()
    }
    
    func didReceiveMnemonic() {
        
        self.createWalletLabel.alpha = 1
        self.nextButtonSpinner.stopAnimating()
        
        if nextTapped == true {
            let notificationDict:[String: Any] = ["page":"0"]
            NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "signupnext"), object: nil, userInfo: notificationDict) as Notification)
            nextTapped = false
        }
    }
    
    @IBAction func articleButtonTapped(_ sender: UIButton) {
        let notificationDict:[String: Any] = ["tag":sender.accessibilityIdentifier]
        NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "launcharticle"), object: nil, userInfo: notificationDict) as Notification)
    }
    
    func changeColors() {
        self.topLabel.textColor = Colors.getColor("blackorwhite")
        if CacheManager.darkModeIsOn() {
            self.restoreLabel.textColor = Colors.getColor("blackorwhite")
        } else {
            self.restoreLabel.textColor = Colors.getColor("transparentblack")
        }
    }
    
    func setWords() {
        
        self.headerLabel.text = Language.getWord(withID: "welcome")
        self.topLabel.text = Language.getWord(withID: "createyourownwallet")
        self.createWalletLabel.text = Language.getWord(withID: "createwallet")
        self.restoreLabel.text = Language.getWord(withID: "restorewallet")
    }
    
}
