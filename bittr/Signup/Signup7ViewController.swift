//
//  Signup7ViewController.swift
//  bittr
//
//  Created by Tom Melters on 02/06/2023.
//

import UIKit

class Signup7ViewController: UIViewController {

    // Confirmation of created wallet. Sign up with bittr or skip directly to wallet.
    
    // Checkmark
    @IBOutlet weak var checkView: UIView!
    @IBOutlet weak var checkmarkImage: UIImageView!
    
    // Top labels
    @IBOutlet weak var topLabelOne: UILabel!
    @IBOutlet weak var topLabelTwo: UILabel!
    @IBOutlet weak var topLabelTwoTop: NSLayoutConstraint!
    
    // Selection
    @IBOutlet weak var partnerView: UIView!
    @IBOutlet weak var partnerButton: UIButton!
    @IBOutlet weak var continueView: UIView!
    @IBOutlet weak var continueLabel: UILabel!
    @IBOutlet weak var continueButton: UIButton!
    @IBOutlet weak var skipButton: UIButton!
    @IBOutlet weak var skipLabel: UILabel!
    
    // Article
    @IBOutlet weak var cardView: UIView!
    @IBOutlet weak var imageContainer: UIView!
    @IBOutlet weak var articleButton: UIButton!
    @IBOutlet weak var spinner1: UIActivityIndicatorView!
    @IBOutlet weak var articleImage: UIImageView!
    @IBOutlet weak var articleTitle: UILabel!
    let pageArticle1Slug = "what-is-bittr"
    var pageArticle1 = Article()
    var embeddedInBuyVC = false
    var coreVC:CoreViewController?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Corner radii.
        checkView.layer.cornerRadius = 25
        partnerView.layer.cornerRadius = 13
        continueView.layer.cornerRadius = 13
        cardView.layer.cornerRadius = 13
        imageContainer.layer.cornerRadius = 13
        
        // Button titles
        partnerButton.setTitle("", for: .normal)
        continueButton.setTitle("", for: .normal)
        skipButton.setTitle("", for: .normal)
        articleButton.setTitle("", for: .normal)
        
        // Notification observers.
        NotificationCenter.default.addObserver(self, selector: #selector(updateArticle), name: NSNotification.Name(rawValue: "setsignuparticles"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(updateArticle), name: NSNotification.Name(rawValue: "setimage\(pageArticle1Slug)"), object: nil)
        
        self.changeColors()
        self.setWords()
    }
    
    @IBAction func skipButtonTapped(_ sender: UIButton) {
        
        // Close sign up and proceed into wallet.
        NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "restorewallet"), object: nil, userInfo: nil) as Notification)
        self.coreVC?.setClient()
    }
    
    @IBAction func partnerButtonTapped(_ sender: UIButton) {
    }
    
    @IBAction func nextButtonTapped(_ sender: UIButton) {
        
        // Proceed to bittr signup.
        let notificationDict:[String: Any] = ["page":sender.accessibilityIdentifier]
        NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "signupnext"), object: nil, userInfo: notificationDict) as Notification)
    }
    
    @IBAction func articleButtonTapped(_ sender: UIButton) {
        
        let notificationDict:[String: Any] = ["tag":sender.accessibilityIdentifier]
        
        NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "launcharticle"), object: nil, userInfo: notificationDict) as Notification)
    }
    
    func changeColors() {
        
        self.topLabelOne.textColor = Colors.getColor("blackorwhite")
        self.topLabelTwo.textColor = Colors.getColor("blackorwhite")
        
        if CacheManager.darkModeIsOn() {
            self.skipLabel.textColor = Colors.getColor("blackorwhite")
        } else {
            self.skipLabel.textColor = Colors.getColor("transparentblack")
        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        if self.embeddedInBuyVC == true {
            self.checkView.alpha = 0
            self.topLabelOne.alpha = 0
            self.topLabelTwo.font = UIFont(name: "Gilroy-Bold", size: 16)
            self.topLabelTwoTop.constant = -86
            self.skipLabel.alpha = 0
            self.skipButton.alpha = 0
            self.view.layoutIfNeeded()
        }
        
        self.updateArticle()
    }
    
    @objc func updateArticle() {
        DispatchQueue.main.async {
            if self.coreVC != nil {
                if self.coreVC!.allArticles != nil {
                    if let thisArticle = self.coreVC!.allArticles![self.pageArticle1Slug] {
                        
                        self.pageArticle1 = thisArticle
                        self.articleTitle.text = self.pageArticle1.title
                        self.articleButton.accessibilityIdentifier = self.pageArticle1Slug
                        
                        if let imageData = CacheManager.getImage(key: self.pageArticle1.image) {
                            self.spinner1.stopAnimating()
                            self.articleImage.image = UIImage(data: imageData)
                        } else {
                            
                        }
                    }
                }
            }
        }
    }
    
    func setWords() {
        
        self.topLabelOne.text = Language.getWord(withID: "walletisready")
        self.topLabelTwo.text = Language.getWord(withID: "firstbitcoin")
        self.continueLabel.text = Language.getWord(withID: "next")
        self.skipLabel.text = Language.getWord(withID: "skip")
    }
    
}
