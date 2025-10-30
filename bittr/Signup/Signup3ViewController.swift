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
    
    // Next button
    @IBOutlet weak var saveView: UIView!
    @IBOutlet weak var nextButton: UIButton!
    @IBOutlet weak var nextLabel: UILabel!
    
    // Mnemonic stack
    @IBOutlet weak var mnemonicView: UIView!
    @IBOutlet weak var mnemonicStack: UIView!
    
    // Scroll view and contents
    @IBOutlet weak var centerView: UIView!
    @IBOutlet weak var contentView: UIView!
    @IBOutlet weak var scrollView: UIScrollView!
    @IBOutlet weak var contentViewHeight: NSLayoutConstraint!
    @IBOutlet weak var centerViewCenterY: NSLayoutConstraint!
    
    // Article
    @IBOutlet weak var articleButton: UIButton!
    @IBOutlet weak var articleView: UIView!
    @IBOutlet weak var spinner1: UIActivityIndicatorView!
    @IBOutlet weak var articleImage: UIImageView!
    @IBOutlet weak var imageContainer: UIView!
    @IBOutlet weak var articleTitle: UILabel!
    let pageArticle1Slug = "wallet-recovery"
    var pageArticle1 = Article()
    
    // Upper VCs
    var coreVC:CoreViewController?
    var signupVC:SignupViewController?
    
    override func viewDidLoad() {
        super.viewDidLoad()

        // Corner radii
        self.saveView.layer.cornerRadius = 13
        self.articleView.layer.cornerRadius = 13
        self.imageContainer.layer.cornerRadius = 13
        
        // Button titles
        self.articleButton.setTitle("", for: .normal)
        self.nextButton.setTitle("", for: .normal)
        
        // Card styling
        self.articleView.layer.shadowColor = UIColor.black.cgColor
        self.articleView.layer.shadowOffset = CGSize(width: 0, height: 8)
        self.articleView.layer.shadowRadius = 12.0
        self.articleView.layer.shadowOpacity = 0.05
        
        // Yellow card styling
        self.mnemonicView.layer.cornerRadius = 13
        self.mnemonicView.layer.shadowColor = UIColor.black.cgColor
        self.mnemonicView.layer.shadowOffset = CGSize(width: 0, height: 7)
        self.mnemonicView.layer.shadowRadius = 10.0
        self.mnemonicView.layer.shadowOpacity = 0.1
        
        // Words and colors
        self.changeColors()
        self.setWords()
        self.setMnemonic()
        Task {
            await self.setSignupArticle(articleSlug: self.pageArticle1Slug, coreVC: self.signupVC!.coreVC!, articleButton: self.articleButton, articleTitle: self.articleTitle, articleImage: self.articleImage, articleSpinner: self.spinner1, completion: { article in
                self.pageArticle1 = article ?? Article()
            })
        }
    }
    
    func setMnemonic() {
        
        // Step 8.
        if let actualMnemonic = self.signupVC?.coreVC?.newMnemonic {
            for (index, eachWord) in actualMnemonic.enumerated() {
                
                let whiteCard = UIView()
                whiteCard.translatesAutoresizingMaskIntoConstraints = false
                whiteCard.layer.cornerRadius = 8
                whiteCard.backgroundColor = Colors.getColor("whiteorblue3")
                self.mnemonicStack.addSubview(whiteCard)
                
                let whiteCardTop = NSLayoutConstraint(item: whiteCard, attribute: .top, relatedBy: .equal, toItem: self.mnemonicStack, attribute: .top, multiplier: 1, constant: CGFloat(index)*55)
                let whiteCardLeft = NSLayoutConstraint(item: whiteCard, attribute: .leading, relatedBy: .equal, toItem: self.mnemonicStack, attribute: .leading, multiplier: 1, constant: 10)
                let whiteCardRight = NSLayoutConstraint(item: whiteCard, attribute: .trailing, relatedBy: .equal, toItem: self.mnemonicStack, attribute: .trailing, multiplier: 1, constant: -10)
                let whiteCardHeight = NSLayoutConstraint(item: whiteCard, attribute: .height, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 45)
                whiteCard.addConstraint(whiteCardHeight)
                self.mnemonicStack.addConstraints([whiteCardTop, whiteCardLeft, whiteCardRight])
                if index == 11 {
                    let whiteCardBottom = NSLayoutConstraint(item: whiteCard, attribute: .bottom, relatedBy: .equal, toItem: self.mnemonicStack, attribute: .bottom, multiplier: 1, constant: 0)
                    self.mnemonicStack.addConstraint(whiteCardBottom)
                }
                
                let numberLabel = UILabel()
                numberLabel.font = UIFont(name: "Gilroy-Bold", size: 16)
                numberLabel.textColor = Colors.getColor("yellow")
                numberLabel.translatesAutoresizingMaskIntoConstraints = false
                numberLabel.text = "\(index+1)"
                whiteCard.addSubview(numberLabel)
                
                let numberLeft = NSLayoutConstraint(item: numberLabel, attribute: .leading, relatedBy: .equal, toItem: whiteCard, attribute: .leading, multiplier: 1, constant: 20)
                let numberCenterY = NSLayoutConstraint(item: numberLabel, attribute: .centerY, relatedBy: .equal, toItem: whiteCard, attribute: .centerY, multiplier: 1, constant: 1.5)
                let numberWidth = NSLayoutConstraint(item: numberLabel, attribute: .width, relatedBy: .greaterThanOrEqual, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 0)
                let numberHeight = NSLayoutConstraint(item: numberLabel, attribute: .height, relatedBy: .greaterThanOrEqual, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 0)
                numberLabel.addConstraints([numberWidth, numberHeight])
                whiteCard.addConstraints([numberLeft, numberCenterY])
                
                let wordLabel = UILabel()
                wordLabel.font = UIFont(name: "Gilroy-Bold", size: 16)
                wordLabel.textColor = Colors.getColor("blackorwhite")
                wordLabel.translatesAutoresizingMaskIntoConstraints = false
                wordLabel.text = eachWord
                whiteCard.addSubview(wordLabel)
                
                let wordCenterX = NSLayoutConstraint(item: wordLabel, attribute: .centerX, relatedBy: .equal, toItem: whiteCard, attribute: .centerX, multiplier: 1, constant: 0)
                let wordCenterY = NSLayoutConstraint(item: wordLabel, attribute: .centerY, relatedBy: .equal, toItem: whiteCard, attribute: .centerY, multiplier: 1, constant: 1.5)
                let wordWidth = NSLayoutConstraint(item: wordLabel, attribute: .width, relatedBy: .greaterThanOrEqual, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 0)
                let wordHeight = NSLayoutConstraint(item: wordLabel, attribute: .height, relatedBy: .greaterThanOrEqual, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 0)
                wordLabel.addConstraints([wordWidth, wordHeight])
                whiteCard.addConstraints([wordCenterX, wordCenterY])
            }
            self.view.layoutIfNeeded()
        }
    }
    
    @IBAction func nextButtonTapped(_ sender: UIButton) {
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
        if sender.accessibilityIdentifier != nil {
            self.coreVC!.launchArticle(articleTag: "\(sender.accessibilityIdentifier!)")
        }
    }
    
    func changeColors() {
        self.topLabelOne.textColor = Colors.getColor("blackorwhite")
        self.topLabelTwo.textColor = Colors.getColor("blackorwhite")
        self.mnemonicView.backgroundColor = Colors.getColor("yelloworblue1")
    }
    
    func setWords() {
        self.topLabelOne.text = Language.getWord(withID: "recoveryphrase")
        self.topLabelTwo.text = Language.getWord(withID: "recoveryphrase2")
        self.nextLabel.text = Language.getWord(withID: "next")
    }

}
