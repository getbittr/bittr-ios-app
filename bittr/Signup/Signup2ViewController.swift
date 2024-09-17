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
    
    // Article
    @IBOutlet weak var imageContainer: UIView!
    @IBOutlet weak var articleButton: UIButton!
    @IBOutlet weak var spinner1: UIActivityIndicatorView!
    @IBOutlet weak var articleImage: UIImageView!
    @IBOutlet weak var articleTitle: UILabel!
    let pageArticle1Slug = "what-is-a-bitcoin-wallet"
    var pageArticle1 = Article()
    
    override func viewDidLoad() {
        super.viewDidLoad()

        // Corner radii and button titles.
        buttonView.layer.cornerRadius = 13
        nextButton.setTitle("", for: .normal)
        cardView.layer.cornerRadius = 13
        cardView.layer.shadowColor = UIColor.black.cgColor
        cardView.layer.shadowOffset = CGSize(width: 0, height: 8)
        cardView.layer.shadowRadius = 12.0
        cardView.layer.shadowOpacity = 0.05
        imageContainer.layer.cornerRadius = 13
        articleButton.setTitle("", for: .normal)
        
        // Notification observers.
        NotificationCenter.default.addObserver(self, selector: #selector(setSignupArticles), name: NSNotification.Name(rawValue: "setsignuparticles"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(setArticleImage), name: NSNotification.Name(rawValue: "setimage\(pageArticle1Slug)"), object: nil)
        
        self.changeColors()
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
            
            let notificationDict:[String: Any] = ["page":sender.accessibilityIdentifier]
            NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "signupnext"), object: nil, userInfo: notificationDict) as Notification)
        }
    }
    
    @IBAction func articleButtonTapped(_ sender: UIButton) {
        
        let notificationDict:[String: Any] = ["tag":sender.accessibilityIdentifier]
        NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "launcharticle"), object: nil, userInfo: notificationDict) as Notification)
    }
    
    func changeColors() {
        self.topLabel.textColor = Colors.getColor(color: "black")
        
        //self.cardView.backgroundColor = Colors.getColor(color: "cardview")
        //self.articleTitle.textColor = Colors.getColor(color: "black")
        
        self.labelOne.textColor = Colors.getColor(color: "black")
        self.labelTwo.textColor = Colors.getColor(color: "black")
    }
    
}
