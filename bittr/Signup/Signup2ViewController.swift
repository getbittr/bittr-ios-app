//
//  Signup2ViewController.swift
//  bittr
//
//  Created by Tom Melters on 22/05/2023.
//

import UIKit

class Signup2ViewController: UIViewController {

    // View for the user to confirm that they understand how to maintain a bitcoin wallet.
    
    @IBOutlet weak var topLabel: UILabel!
    
    // Switches
    @IBOutlet weak var switchOne: UISwitch!
    @IBOutlet weak var switchTwo: UISwitch!
    @IBOutlet weak var labelOne: UILabel!
    @IBOutlet weak var labelTwo: UILabel!
    
    // Next button and article
    @IBOutlet weak var cardView: UIView!
    @IBOutlet weak var buttonView: UIView!
    @IBOutlet weak var nextButton: UIButton!
    @IBOutlet weak var nextLabel: UILabel!
    
    // Cancel button
    @IBOutlet weak var cancelButton: UIButton!
    @IBOutlet weak var cancelLabel: UILabel!
    
    // Article
    @IBOutlet weak var imageContainer: UIView!
    @IBOutlet weak var articleButton: UIButton!
    @IBOutlet weak var spinner1: UIActivityIndicatorView!
    @IBOutlet weak var articleImage: UIImageView!
    @IBOutlet weak var articleTitle: UILabel!
    let pageArticle1Slug = "what-is-a-bitcoin-wallet"
    var pageArticle1 = Article()
    var coreVC:CoreViewController?
    var signupVC:SignupViewController?
    
    override func viewDidLoad() {
        super.viewDidLoad()

        // Corner radii
        self.buttonView.layer.cornerRadius = 13
        self.cardView.layer.cornerRadius = 13
        self.imageContainer.layer.cornerRadius = 13
        
        // Button titles
        self.articleButton.setTitle("", for: .normal)
        self.nextButton.setTitle("", for: .normal)
        self.cancelButton.setTitle("", for: .normal)
        
        // Card styling
        self.cardView.layer.shadowColor = UIColor.black.cgColor
        self.cardView.layer.shadowOffset = CGSize(width: 0, height: 8)
        self.cardView.layer.shadowRadius = 12.0
        self.cardView.layer.shadowOpacity = 0.05
        
        self.changeColors()
        self.setWords()
        Task {
            await self.setSignupArticle(articleSlug: self.pageArticle1Slug, coreVC: self.signupVC!.coreVC!, articleButton: self.articleButton, articleTitle: self.articleTitle, articleImage: self.articleImage, articleSpinner: self.spinner1, completion: { article in
                self.pageArticle1 = article ?? Article()
            })
        }
    }
    
    @IBAction func switchChanged(_ sender: UISwitch) {
        
        // Make Next button clickable.
        if switchOne.isOn == true && switchTwo.isOn == true {
            // Clickable. Both switches are on.
            self.buttonView.backgroundColor = UIColor(red: 0, green: 0, blue: 0, alpha: 1)
        } else {
            // Not clickable.
            self.buttonView.backgroundColor = UIColor(red: 0, green: 0, blue: 0, alpha: 0.6)
        }
    }
    
    @IBAction func nextButtonTapped(_ sender: UIButton) {
        
        if switchOne.isOn == true && switchTwo.isOn == true {
            self.signupVC?.moveToPage(5)
        }
    }
    
    @IBAction func articleButtonTapped(_ sender: UIButton) {
        if sender.accessibilityIdentifier != nil {
            self.coreVC!.infoVC!.launchArticle(articleTag: "\(sender.accessibilityIdentifier!)")
        }
    }
    
    @IBAction func backButtonTapped(_ sender: UIButton) {
        
        self.view.endEditing(true)
        
        if self.signupVC == nil {
            return
        } else {
            // Go back to wallet choice screen (create or restore)
            self.signupVC?.moveToPage(3)
        }
    }
    
    func changeColors() {
        
        self.topLabel.textColor = Colors.getColor("blackorwhite")
        self.labelOne.textColor = Colors.getColor("blackorwhite")
        self.labelTwo.textColor = Colors.getColor("blackorwhite")
        self.cancelLabel.textColor = Colors.getColor("transparentblack")
    }
    
    func setWords() {
        
        self.topLabel.text = Language.getWord(withID: "checkandconfirm")
        self.labelOne.text = Language.getWord(withID: "checkandconfirm1")
        self.labelTwo.text = Language.getWord(withID: "checkandconfirm2")
        self.nextLabel.text = Language.getWord(withID: "iunderstand")
        self.cancelLabel.text = Language.getWord(withID: "cancel")
    }
    
}
