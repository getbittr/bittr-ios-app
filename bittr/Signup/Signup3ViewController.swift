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
    var signupVC:SignupViewController?
    
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

        // Corner radii
        self.saveView.layer.cornerRadius = 13
        self.cardView.layer.cornerRadius = 13
        self.imageContainer.layer.cornerRadius = 13
        self.mnemonicView.layer.cornerRadius = 13
        
        // Button titles
        self.articleButton.setTitle("", for: .normal)
        self.nextButton.setTitle("", for: .normal)
        
        // Card styling
        self.cardView.layer.shadowColor = UIColor.black.cgColor
        self.cardView.layer.shadowOffset = CGSize(width: 0, height: 8)
        self.cardView.layer.shadowRadius = 12.0
        self.cardView.layer.shadowOpacity = 0.05
        
        // Words and colors
        self.changeColors()
        self.setWords2()
        self.setMnemonic()
        Task {
            await self.setSignupArticle(articleSlug: self.pageArticle1Slug, coreVC: self.signupVC!.coreVC!, articleButton: self.articleButton, articleTitle: self.articleTitle, articleImage: self.articleImage, articleSpinner: self.spinner1, completion: { article in
                self.pageArticle1 = article ?? Article()
            })
        }
    }
    
    func setMnemonic() {
        
        // Step 8.
        if self.signupVC?.coreVC == nil { print("CoreVC nil in Signup3.") }
        if let actualMnemonic = self.signupVC?.coreVC?.newMnemonic {
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
    
    @IBAction func nextButtonTapped(_ sender: UIButton) {
        
        /*let notificationDict:[String: Any] = ["page":sender.accessibilityIdentifier]
        NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "signupnext"), object: nil, userInfo: notificationDict) as Notification)*/
        
        self.signupVC?.moveToPage(6)
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
        self.coreVC!.infoVC!.launchArticle(articleTag: "\(sender.accessibilityIdentifier!)")
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
