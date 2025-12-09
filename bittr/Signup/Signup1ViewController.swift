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
    
    // Header view
    @IBOutlet weak var centerCard: UIView!
    @IBOutlet weak var headerPiggyImage: UIImageView!
    @IBOutlet weak var headerLabel: UILabel!
    @IBOutlet weak var topLabel: UILabel!
    
    // Next button
    @IBOutlet weak var createWalletView: UIView!
    @IBOutlet weak var createWalletButton: UIButton!
    @IBOutlet weak var createWalletLabel: UILabel!
    @IBOutlet weak var createWalletArrow: UIImageView!
    @IBOutlet weak var createWalletSpinner: UIActivityIndicatorView!
    
    // Restore button
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
    
    // Variables
    var coreVC:CoreViewController?
    var signupVC:SignupViewController?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Corner radii
        self.createWalletView.layer.cornerRadius = 8
        self.cardView.layer.cornerRadius = 8
        self.imageContainer.layer.cornerRadius = 8
        
        // Center card
        self.centerCard.layer.cornerRadius = 13
        self.centerCard.setShadow()
        
        // Button titles
        self.createWalletButton.setTitle("", for: .normal)
        self.restoreButton.setTitle("", for: .normal)
        self.articleButton.setTitle("", for: .normal)
        
        // Card styling
        self.cardView.setShadow()
        
        // Set colors, words, article.
        self.changeColors()
        self.setWords()
        Task {
            await self.setSignupArticle(articleSlug: self.pageArticle1Slug, coreVC: self.signupVC!.coreVC!, articleButton: self.articleButton, articleTitle: self.articleTitle, articleImage: self.articleImage, articleSpinner: self.spinner1, completion: { article in
                self.pageArticle1 = article ?? Article()
            })
        }
    }
    
    @IBAction func restoreButtonClicked(_ sender: UIButton) {
        
        self.signupVC?.moveToPage(2)
    }
    
    @IBAction func nextButtonTapped(_ sender: UIButton) {
        
        // Check internet connection.
        if !Reachability.isConnectedToNetwork() {
            // User not connected to internet.
            self.showAlert(presentingController: self.signupVC?.coreVC ?? self.signupVC ?? self, title: Language.getWord(withID: "checkyourconnection"), message: Language.getWord(withID: "trytoconnect"), buttons: [Language.getWord(withID: "okay")], actions: nil)
            return
        }
        
        // Start spinner.
        self.createWalletLabel.alpha = 0
        self.createWalletArrow.alpha = 0
        self.createWalletSpinner.startAnimating()
        
        // Delay the call 1 second to keep the spinner visible for a moment.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            
            // Get mnemonic.
            let _ = LightningNodeService.shared.getMnemonic()
            
            // Stop spinner.
            self.createWalletLabel.alpha = 1
            self.createWalletArrow.alpha = 1
            self.createWalletSpinner.stopAnimating()
            self.signupVC?.moveToPage(4)
        }
    }
    
    @IBAction func articleButtonTapped(_ sender: UIButton) {
        if sender.accessibilityIdentifier != nil {
            self.coreVC!.launchArticle(articleTag: "\(sender.accessibilityIdentifier!)")
        }
    }
    
    func changeColors() {
        
        self.topLabel.textColor = Colors.getColor("blackorwhite")
        self.headerLabel.textColor = Colors.getColor("whiteoryellow")
        self.centerCard.backgroundColor = Colors.getColor("yelloworblue1")
        
        if CacheManager.darkModeIsOn() {
            self.restoreLabel.textColor = Colors.getColor("blackorwhite")
            self.headerPiggyImage.image = UIImage(named: "iconpiggyyellow")
        } else {
            self.restoreLabel.textColor = Colors.getColor("transparentblack")
            self.headerPiggyImage.image = UIImage(named: "iconpiggywhite")
        }
    }
    
    func setWords() {
        
        self.headerLabel.text = Language.getWord(withID: "welcome")
        self.topLabel.text = Language.getWord(withID: "createyourownwallet")
        self.createWalletLabel.text = Language.getWord(withID: "createwallet")
        self.restoreLabel.text = Language.getWord(withID: "restorewallet")
    }
}
