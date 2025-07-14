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
    
    // Variables
    let pageArticle1Slug = "what-is-bittr"
    var pageArticle1 = Article()
    var embeddedInBuyVC = false
    var coreVC:CoreViewController?
    var signupVC:SignupViewController?
    var ibanVC:RegisterIbanViewController?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Corner radii.
        self.checkView.layer.cornerRadius = 25
        self.partnerView.layer.cornerRadius = 13
        self.continueView.layer.cornerRadius = 13
        self.cardView.layer.cornerRadius = 13
        self.imageContainer.layer.cornerRadius = 13
        
        // Button titles
        self.partnerButton.setTitle("", for: .normal)
        self.continueButton.setTitle("", for: .normal)
        self.skipButton.setTitle("", for: .normal)
        self.articleButton.setTitle("", for: .normal)
        
        self.changeColors()
        self.setWords()
        Task {
            await self.setSignupArticle(articleSlug: self.pageArticle1Slug, coreVC: self.signupVC?.coreVC ?? self.coreVC!, articleButton: self.articleButton, articleTitle: self.articleTitle, articleImage: self.articleImage, articleSpinner: self.spinner1, completion: { article in
                self.pageArticle1 = article ?? Article()
            })
        }
    }
    
    @IBAction func skipButtonTapped(_ sender: UIButton) {
        
        // Close sign up and proceed into wallet.
        self.coreVC!.buyVC?.registerIbanVC?.dismiss(animated: true)
        self.coreVC!.buyVC?.parseIbanEntities()
        self.coreVC!.hideSignup()
    }
    
    @IBAction func partnerButtonTapped(_ sender: UIButton) {
    }
    
    @IBAction func nextButtonTapped(_ sender: UIButton) {
        
        // Proceed to bittr signup.
        self.signupVC?.moveToPage(10)
        self.ibanVC?.moveToPage(10)
    }
    
    @IBAction func articleButtonTapped(_ sender: UIButton) {
        if sender.accessibilityIdentifier != nil {
            self.coreVC!.infoVC!.launchArticle(articleTag: "\(sender.accessibilityIdentifier!)")
        }
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
    }
    
    func setWords() {
        
        self.topLabelOne.text = Language.getWord(withID: "walletisready")
        self.topLabelTwo.text = Language.getWord(withID: "firstbitcoin")
        self.continueLabel.text = Language.getWord(withID: "next")
        self.skipLabel.text = Language.getWord(withID: "skip")
    }
    
}
