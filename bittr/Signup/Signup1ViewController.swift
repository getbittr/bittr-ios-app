//
//  Signup1ViewController.swift
//  bittr
//
//  Created by Tom Melters on 22/05/2023.
//

import UIKit

class Signup1ViewController: UIViewController {

    @IBOutlet weak var headerView: UIView!
    @IBOutlet weak var buttonView: UIView!
    @IBOutlet weak var nextButton: UIButton!
    @IBOutlet weak var restoreView: UIView!
    @IBOutlet weak var restoreButton: UIButton!
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
    
    override func viewDidLoad() {
        super.viewDidLoad()

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
        NotificationCenter.default.addObserver(self, selector: #selector(didReceiveMnemonic), name: NSNotification.Name(rawValue: "setwords"), object: nil)
    }
    
    
    @objc func didReceiveMnemonic() {
        
        // Step 7.
        
        self.createWalletLabel.alpha = 1
        self.nextButtonSpinner.stopAnimating()
        
        if nextTapped == true {
            let notificationDict:[String: Any] = ["page":"0"]
            NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "signupnext"), object: nil, userInfo: notificationDict) as Notification)
            nextTapped = false
        }
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
    

    @IBAction func restoreButtonClicked(_ sender: UIButton) {
        
        /*let alert = UIAlertController(title: "Oops!", message: "It's currently not possible to restore another wallet into our app. Please contact us if you have questions.", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Okay", style: .cancel, handler: nil))
        self.present(alert, animated: true)
        return*/
        
        let notificationDict:[String: Any] = ["page":sender.accessibilityIdentifier]
        NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "signupnext"), object: nil, userInfo: notificationDict) as Notification)
    }
    
    @IBAction func nextButtonTapped(_ sender: UIButton) {
        
        self.createWalletLabel.alpha = 0
        self.nextButtonSpinner.startAnimating()
        self.nextTapped = true
        
        NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "startlightning"), object: nil, userInfo: nil) as Notification)
    }
    
    @IBAction func articleButtonTapped(_ sender: UIButton) {
        let notificationDict:[String: Any] = ["tag":sender.accessibilityIdentifier]
        NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "launcharticle"), object: nil, userInfo: notificationDict) as Notification)
    }
    
}
