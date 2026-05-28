//
//  Signup7ViewController.swift
//  bittr
//
//  Created by Tom Melters on 02/06/2023.
//

import UIKit
import Sentry

class Signup7ViewController: UIViewController {

    // Confirmation of created wallet. Sign up with bittr or skip directly to wallet.
    
    // Top items
    @IBOutlet weak var centerCard: UIView!
    @IBOutlet weak var checkView: UIView!
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
    
    // Variables
    var coreVC:CoreViewController?
    var signupVC:SignupViewController?
    var ibanVC:RegisterIbanViewController?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Corner radii.
        self.checkView.layer.cornerRadius = 25
        self.partnerView.layer.cornerRadius = 8
        self.continueView.layer.cornerRadius = 8
        self.cardView.layer.cornerRadius = 8
        self.imageContainer.layer.cornerRadius = 8
        self.centerCard.layer.cornerRadius = 13
        self.cardView.setShadow()
        self.centerCard.setShadow()
        
        // Button titles
        self.partnerButton.setTitle("", for: .normal)
        self.continueButton.setTitle("", for: .normal)
        self.skipButton.setTitle("", for: .normal)
        self.articleButton.setTitle("", for: .normal)
        
        self.topLabelOne.accessibilityIdentifier = TestID.Signup.Create.Ready.topLabelOne
        self.continueButton.accessibilityIdentifier = TestID.Signup.Create.Ready.continueButton
        self.skipButton.accessibilityIdentifier = TestID.Signup.Create.Ready.skipButton

        // Set language, colors, article.
        self.changeColors()
        self.setWords()
        Task {
            await self.setSignupArticle(articleSlug: self.pageArticle1Slug, coreVC: self.signupVC?.coreVC ?? self.coreVC!, articleButton: self.articleButton, articleTitle: self.articleTitle, articleImage: self.articleImage, articleSpinner: self.spinner1, completion: { article in
                self.pageArticle1 = article ?? Article()
            })
        }
    }
    
    @IBAction func skipButtonTapped(_ sender: UIButton) {
        
        if self.coreVC!.buyVC == nil {
            // Count initial signup skip.
            SentrySDK.metrics.count(key: "app.launch.newwallet.signup.skip")
        }
        
        // Close sign up and proceed into wallet.
        self.coreVC!.buyVC?.registerIbanVC?.dismiss(animated: true)
        self.coreVC!.buyVC?.parseIbanEntities(uponPageLaunch: false)
        self.coreVC!.hideSignup()
    }
    
    @IBAction func partnerButtonTapped(_ sender: UIButton) {
    }
    
    @IBAction func nextButtonTapped(_ sender: UIButton) {
        
        if self.coreVC!.buyVC == nil {
            // Count initial signup start.
            SentrySDK.metrics.count(key: "app.launch.newwallet.signup.start")
        }
        
        // Proceed to bittr signup.
        self.signupVC?.moveToPage(10)
        self.ibanVC?.moveToPage(1)
    }
    
    @IBAction func articleButtonTapped(_ sender: UIButton) {
        if let slug = sender.articleSlug {
            self.coreVC!.launchArticle(articleTag: slug)
        }
    }
    
    func changeColors() {
        
        self.topLabelOne.textColor = Colors.getColor("blackorwhite")
        self.topLabelTwo.textColor = Colors.getColor("blackorwhite")
        self.centerCard.backgroundColor = Colors.getColor("yelloworblue1")
        
        if CacheManager.darkModeIsOn() {
            self.skipLabel.textColor = Colors.getColor("blackorwhite")
        } else {
            self.skipLabel.textColor = Colors.getColor("transparentblack")
        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        
        if self.ibanVC != nil {
            // We're in the Buy section, no need to show the "Wallet is ready" confirmation.
            self.checkView.alpha = 0
            self.topLabelOne.alpha = 0
            self.topLabelTwo.font = UIFont(name: "Gilroy-Bold", size: 16)
            self.topLabelTwoTop.constant = -76
            self.skipLabel.alpha = 0
            self.skipButton.alpha = 0
            self.view.layoutIfNeeded()
        }
    }
    
    func setWords() {
        
        self.topLabelOne.text = Language.getWord(withID: "walletisready")
        self.topLabelTwo.text = Language.getWord(withID: "firstbitcoin")
        self.continueLabel.text = Language.getWord(withID: "next")
        self.skipLabel.text = Language.getWord(withID: "skip")
    }
    
}
