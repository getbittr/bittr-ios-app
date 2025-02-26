//
//  Signup3ViewController.swift
//  bittr
//
//  Created by Tom Melters on 24/05/2023.
//

import UIKit

class Signup3ViewController: UIViewController {

    // View showing the user their mnemonic.
    
    // Labels
    @IBOutlet weak var topLabelOne: UILabel!
    @IBOutlet weak var topLabelTwo: UILabel!
    
    @IBOutlet weak var saveView: UIView!
    @IBOutlet weak var cardView: UIView!
    @IBOutlet weak var nextButton: UIButton!
    @IBOutlet weak var nextLabel: UILabel!
    @IBOutlet weak var imageContainer: UIView!
    @IBOutlet weak var mnemonicView: UIView!
    @IBOutlet weak var centerView: UIView!
    @IBOutlet weak var contentView: UIView!
    @IBOutlet weak var scrollView: UIScrollView!
    @IBOutlet weak var contentViewHeight: NSLayoutConstraint!
    @IBOutlet weak var centerViewCenterY: NSLayoutConstraint!
    @IBOutlet weak var articleButton: UIButton!
    
    // Article elements.
    @IBOutlet weak var spinner1: UIActivityIndicatorView!
    @IBOutlet weak var articleImage: UIImageView!
    @IBOutlet weak var articleTitle: UILabel!
    let pageArticle1Slug = "wallet-recovery"
    var pageArticle1 = Article()
    var coreVC:CoreViewController?
    
    // Mnemonic word labels.
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

        // Corner radii and button titles.
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
        
        // Notification observers.
        NotificationCenter.default.addObserver(self, selector: #selector(setSignupArticles), name: NSNotification.Name(rawValue: "setsignuparticles"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(setArticleImage), name: NSNotification.Name(rawValue: "setimage\(pageArticle1Slug)"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(setWords), name: NSNotification.Name(rawValue: "setwords"), object: nil)
        
        self.changeColors()
        self.setWords2()
    }
    
    @objc func setWords(notification:NSNotification) {
        
        // Step 8.
        if self.coreVC == nil { print("CoreVC nil in Signup3.") }
        if let actualMnemonic = self.coreVC?.newMnemonic {
            self.word1.text = actualMnemonic[0]
            self.word2.text = actualMnemonic[1]
            self.word3.text = actualMnemonic[2]
            self.word4.text = actualMnemonic[3]
            self.word5.text = actualMnemonic[4]
            self.word6.text = actualMnemonic[5]
            self.word7.text = actualMnemonic[6]
            self.word8.text = actualMnemonic[7]
            self.word9.text = actualMnemonic[8]
            self.word10.text = actualMnemonic[9]
            self.word11.text = actualMnemonic[10]
            self.word12.text = actualMnemonic[11]
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
    }
    
    override func viewDidAppear(_ animated: Bool) {
        
        let centerViewHeight = centerView.bounds.height
        
        // Make sure view is scrollable for smaller phone screens.
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
    
    func changeColors() {
        
        self.topLabelOne.textColor = Colors.getColor("blackorwhite")
        self.topLabelTwo.textColor = Colors.getColor("blackorwhite")
    }
    
    func setWords2() {
        
        self.topLabelOne.text = Language.getWord(withID: "recoveryphrase")
        self.topLabelTwo.text = Language.getWord(withID: "recoveryphrase2")
        self.nextLabel.text = Language.getWord(withID: "next")
    }

}
