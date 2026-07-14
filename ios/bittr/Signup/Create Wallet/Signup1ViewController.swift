//
//  Signup1ViewController.swift
//  bittr
//
//  Created by Tom Melters on 22/05/2023.
//

import UIKit

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
        
        self.headerLabel.accessibilityIdentifier = TestID.Signup.Create.Start.headerLabel
        self.createWalletButton.accessibilityIdentifier = TestID.Signup.Create.Start.createWalletButton
        self.restoreButton.accessibilityIdentifier = TestID.Signup.Create.Start.restoreButton
        self.articleButton.accessibilityIdentifier = TestID.Signup.Create.Start.articleButton

        // Set colors, words, article.
        self.setWords()
        self.pageArticle1 = self.setSignupArticle(articleSlug: self.pageArticle1Slug, coreVC: self.signupVC!.coreVC!, articleButton: self.articleButton, articleTitle: self.articleTitle, articleImage: self.articleImage, articleSpinner: self.spinner1) ?? Article()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        self.changeColors()
    }
    
    @IBAction func restoreButtonClicked(_ sender: UIButton) {
        
        self.signupVC?.moveToPage(2)
    }
    
    @IBAction func nextButtonTapped(_ sender: UIButton) {
        
        // Check internet connection.
        guard (self.signupVC?.coreVC ?? self.signupVC ?? self).checkInternetConnection() else { return }
        
        // Start spinner.
        self.createWalletLabel.alpha = 0
        self.createWalletArrow.alpha = 0
        self.createWalletSpinner.startAnimating()
        
        // Delay the call 1 second to keep the spinner visible for a moment.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            
            // Stop spinner.
            self.createWalletLabel.alpha = 1
            self.createWalletArrow.alpha = 1
            self.createWalletSpinner.stopAnimating()

            // Create and persist the wallet's mnemonic. If it can't be securely
            // stored, abort loudly rather than continuing with an unsaved seed —
            // a wallet the user then funds would otherwise be unrecoverable.
            do {
                _ = try BitcoinManager.shared.getNewMnemonic()
            } catch {
                self.showAlert(presentingController: self.signupVC?.coreVC ?? self.signupVC ?? self, title: Language.getWord(withID: "error"), message: Language.getWord(withID: "mnemonicsavefail"), buttons: [Language.getWord(withID: "okay")], actions: nil)
                return
            }

            self.signupVC?.moveToPage(4)
        }
    }
    
    @IBAction func articleButtonTapped(_ sender: UIButton) {
        if let slug = sender.boundString {
            self.coreVC!.launchArticle(articleTag: slug)
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
