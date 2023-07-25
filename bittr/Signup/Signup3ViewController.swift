//
//  Signup3ViewController.swift
//  bittr
//
//  Created by Tom Melters on 24/05/2023.
//

import UIKit

class Signup3ViewController: UIViewController {

    @IBOutlet weak var headerView: UIView!
    @IBOutlet weak var saveView: UIView!
    @IBOutlet weak var cardView: UIView!
    @IBOutlet weak var nextButton: UIButton!
    @IBOutlet weak var imageContainer: UIView!
    @IBOutlet weak var mnemonicView: UIView!
    @IBOutlet weak var centerView: UIView!
    @IBOutlet weak var contentView: UIView!
    @IBOutlet weak var scrollView: UIScrollView!
    @IBOutlet weak var contentViewHeight: NSLayoutConstraint!
    @IBOutlet weak var centerViewCenterY: NSLayoutConstraint!
    @IBOutlet weak var articleButton: UIButton!
    
    @IBOutlet weak var spinner1: UIActivityIndicatorView!
    @IBOutlet weak var articleImage: UIImageView!
    @IBOutlet weak var articleTitle: UILabel!
    let pageArticle1Slug = "wallet-recovery"
    var pageArticle1 = Article()
    
    @IBOutlet weak var word1: UILabel!
    @IBOutlet weak var word2: UILabel!
    @IBOutlet weak var word3: UILabel!
    @IBOutlet weak var word4: UILabel!
    @IBOutlet weak var word5: UILabel!
    @IBOutlet weak var word6: UILabel!
    @IBOutlet weak var word7: UILabel!
    @IBOutlet weak var word8: UILabel!
    @IBOutlet weak var word9: UILabel!
    @IBOutlet weak var word10: UILabel!
    @IBOutlet weak var word11: UILabel!
    @IBOutlet weak var word12: UILabel!
    
    override func viewDidLoad() {
        super.viewDidLoad()

        saveView.layer.cornerRadius = 13
        nextButton.setTitle("", for: .normal)
        cardView.layer.cornerRadius = 13
        cardView.layer.shadowColor = UIColor.black.cgColor
        cardView.layer.shadowOffset = CGSize(width: 0, height: 8)
        cardView.layer.shadowRadius = 12.0
        cardView.layer.shadowOpacity = 0.05
        imageContainer.layer.cornerRadius = 13
        mnemonicView.layer.cornerRadius = 13
        articleButton.setTitle("", for: .normal)
        
        NotificationCenter.default.addObserver(self, selector: #selector(setSignupArticles), name: NSNotification.Name(rawValue: "setsignuparticles"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(setArticleImage), name: NSNotification.Name(rawValue: "setimage\(pageArticle1Slug)"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(setWords), name: NSNotification.Name(rawValue: "setwords"), object: nil)
    }
    
    @objc func setWords(notification:NSNotification) {
        
        if let userInfo = notification.userInfo as [AnyHashable:Any]? {
            if let actualMnemonic = userInfo["mnemonic"] as? String {
                
                let individualWords:[String] = actualMnemonic.components(separatedBy: " ")
                self.word1.text = individualWords[0]
                self.word2.text = individualWords[1]
                self.word3.text = individualWords[2]
                self.word4.text = individualWords[3]
                self.word5.text = individualWords[4]
                self.word6.text = individualWords[5]
                self.word7.text = individualWords[6]
                self.word8.text = individualWords[7]
                self.word9.text = individualWords[8]
                self.word10.text = individualWords[9]
                self.word11.text = individualWords[10]
                self.word12.text = individualWords[11]
                
                let checkWords:[String] = [self.word2.text!, self.word7.text!, self.word9.text!]
                let notificationDict = ["words":checkWords]
                NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "setcheckwords"), object: nil, userInfo: notificationDict) as Notification)
            }
        }
    }
    
    @objc func setSignupArticles(notification:NSNotification) {
        
        if let userInfo = notification.userInfo as [AnyHashable:Any]? {
            if let actualArticle = userInfo[pageArticle1Slug] as? Article {
                self.pageArticle1 = actualArticle
                DispatchQueue.main.async {
                    self.articleTitle.text = self.pageArticle1.title
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
    
    @IBAction func nextButtonTapped(_ sender: UIButton) {
        
        let notificationDict:[String: Any] = ["page":sender.accessibilityIdentifier]
         NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "signupnext"), object: nil, userInfo: notificationDict) as Notification)
        
        //NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "restorewallet"), object: nil, userInfo: nil) as Notification)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        
        let centerViewHeight = centerView.bounds.height
        
        if centerView.bounds.height + 40 > contentView.bounds.height {
            
            NSLayoutConstraint.deactivate([self.contentViewHeight])
            self.contentViewHeight = NSLayoutConstraint(item: self.contentView, attribute: .height, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: centerViewHeight)
            NSLayoutConstraint.activate([self.contentViewHeight])
            self.centerViewCenterY.constant = 0
            self.view.layoutIfNeeded()
        }
    }
    
    @IBAction func articleButtonTapped(_ sender: UIButton) {
        
        let notificationDict:[String: Any] = ["tag":sender.accessibilityIdentifier]
        
        NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "launcharticle"), object: nil, userInfo: notificationDict) as Notification)
    }

}
