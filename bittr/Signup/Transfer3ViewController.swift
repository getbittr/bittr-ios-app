//
//  Transfer3ViewController.swift
//  bittr
//
//  Created by Tom Melters on 11/06/2023.
//

import UIKit

class Transfer3ViewController: UIViewController {

    // Views and buttons.
    @IBOutlet weak var headerView: UIView!
    @IBOutlet weak var headerLabel: UILabel!
    @IBOutlet weak var nextView: UIView!
    @IBOutlet weak var nextButton: UIButton!
    @IBOutlet weak var nextLabel: UILabel!
    @IBOutlet weak var cardView: UIView!
    @IBOutlet weak var imageContainer: UIView!
    @IBOutlet weak var cardView2: UIView!
    @IBOutlet weak var imageContainer2: UIView!
    @IBOutlet weak var articleButton: UIButton!
    @IBOutlet weak var articleButton2: UIButton!
    @IBOutlet weak var backButton: UIButton!
    @IBOutlet weak var backLabel: UILabel!
    
    // Labels
    @IBOutlet weak var topLabelOne: UILabel!
    @IBOutlet weak var topLabelTwo: UILabel!
    @IBOutlet weak var topLabelThree: UILabel!
    
    var currentClientID = ""
    var currentIbanID = ""
    
    // Articles.
    @IBOutlet weak var spinner1: UIActivityIndicatorView!
    @IBOutlet weak var articleImage: UIImageView!
    @IBOutlet weak var articleTitle: UILabel!
    let pageArticle1Slug = "bitcoin-lightning"
    var pageArticle1 = Article()
    @IBOutlet weak var spinner2: UIActivityIndicatorView!
    @IBOutlet weak var article2Image: UIImageView!
    @IBOutlet weak var article2Title: UILabel!
    let pageArticle2Slug = "dollar-cost-averaging"
    var pageArticle2 = Article()
    
    @IBOutlet weak var centerView: UIView!
    @IBOutlet weak var contentView: UIView!
    @IBOutlet weak var contentViewHeight: NSLayoutConstraint!
    @IBOutlet weak var centerViewCenterY: NSLayoutConstraint!
    
    var articles:[String:Article]?
    var allImages:[String:UIImage]?
    var coreVC:CoreViewController?
    var signupVC:SignupViewController?
    var ibanVC:RegisterIbanViewController?
    
    override func viewDidLoad() {
        super.viewDidLoad()

        // Corner radii
        self.headerView.layer.cornerRadius = 13
        self.nextView.layer.cornerRadius = 13
        self.cardView.layer.cornerRadius = 13
        self.imageContainer.layer.cornerRadius = 13
        self.cardView2.layer.cornerRadius = 13
        self.imageContainer2.layer.cornerRadius = 13
        
        // Button titles
        self.nextButton.setTitle("", for: .normal)
        self.articleButton.setTitle("", for: .normal)
        self.articleButton2.setTitle("", for: .normal)
        self.backButton.setTitle("", for: .normal)
        
        if let actualImages = allImages {
            if let actualImage = actualImages[pageArticle1Slug] {
                self.articleImage.image = actualImage
            }
            if let actualImage2 = actualImages[pageArticle2Slug] {
                self.article2Image.image = actualImage2
            }
        }
        
        self.changeColors()
        self.setWords()
        self.updateData()
        Task {
            await self.setSignupArticle(articleSlug: self.pageArticle1Slug, coreVC: self.signupVC?.coreVC ?? self.coreVC!, articleButton: self.articleButton, articleTitle: self.articleTitle, articleImage: self.articleImage, articleSpinner: self.spinner1, completion: { article in
                self.pageArticle1 = article ?? Article()
            })
            await self.setSignupArticle(articleSlug: self.pageArticle2Slug, coreVC: self.signupVC?.coreVC ?? self.coreVC!, articleButton: self.articleButton2, articleTitle: self.article2Title, articleImage: self.article2Image, articleSpinner: self.spinner2, completion: { article in
                self.pageArticle2 = article ?? Article()
            })
        }
    }
    
    override func viewDidAppear(_ animated: Bool) {
        
        var centerViewHeight = centerView.bounds.height
        
        if centerView.bounds.height + 40 > contentView.bounds.height {
            
            NSLayoutConstraint.deactivate([self.contentViewHeight])
            self.contentViewHeight = NSLayoutConstraint(item: self.contentView, attribute: .height, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: centerViewHeight + 60)
            NSLayoutConstraint.activate([self.contentViewHeight])
            self.centerViewCenterY.constant = 0
            self.view.layoutIfNeeded()
        }
    }
    
    func updateData() {
        
        if self.signupVC != nil {
            self.currentClientID = self.signupVC!.currentClientID
            self.currentIbanID = self.signupVC!.currentIbanID
        }
    }
    
    @IBAction func nextButtonTapped(_ sender: UIButton) {
        
        var envKey = "proddevice"
        if UserDefaults.standard.value(forKey: "envkey") as? Int == 0 {
            envKey = "device"
        }
        
        let deviceDict = UserDefaults.standard.value(forKey: envKey) as? NSDictionary
        if let actualDeviceDict = deviceDict {
            let clients:[Client] = CacheManager.parseDevice(deviceDict: actualDeviceDict)
            for client in clients {
                if client.id == self.currentClientID {
                    for iban in client.ibanEntities {
                        if iban.id == self.currentIbanID {
                            
                            self.showAlert(presentingController: self, title: Language.getWord(withID: "bankingapp"), message: "\n\(Language.getWord(withID: "bankingapp2"))\n\n\(iban.ourIbanNumber)\n\(iban.ourName)\n\(iban.yourUniqueCode)", buttons: [Language.getWord(withID: "done")], actions: [#selector(self.proceedToWallet)])
                        }
                    }
                }
            }
        }
    }
    
    @objc func proceedToWallet() {
        self.hideAlert()
        // Hide signup and proceed into wallet.
        NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "restorewallet"), object: nil, userInfo: nil) as Notification)
        (self.signupVC?.coreVC ?? self.coreVC!).setClient()
    }
    
    @IBAction func articleButtonTapped(_ sender: UIButton) {
        
        let notificationDict:[String: Any] = ["tag":sender.accessibilityIdentifier]
        
        NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "launcharticle"), object: nil, userInfo: notificationDict) as Notification)
    }
    
    @IBAction func backButtonTapped(_ sender: UIButton) {
        self.signupVC?.moveToPage(12)
        self.ibanVC?.moveToPage(12)
    }
    
    func changeColors() {
        
        self.topLabelOne.textColor = Colors.getColor("blackorwhite")
        self.topLabelTwo.textColor = Colors.getColor("blackorwhite")
        self.topLabelThree.textColor = Colors.getColor("blackorwhite")
        
        if CacheManager.darkModeIsOn() {
            self.backLabel.textColor = Colors.getColor("blackorwhite")
        } else {
            self.backLabel.textColor = Colors.getColor("transparentblack")
        }

    }
    
    func setWords() {
        
        self.headerLabel.text = Language.getWord(withID: "finaldetails")
        self.topLabelOne.text = Language.getWord(withID: "bittrinstructions")
        self.topLabelTwo.text = Language.getWord(withID: "bittrinstructions2")
        self.topLabelThree.text = Language.getWord(withID: "bittrinstructions3")
        self.nextLabel.text = Language.getWord(withID: "letsgo")
        self.backLabel.text = Language.getWord(withID: "back")
        
    }
    
}
