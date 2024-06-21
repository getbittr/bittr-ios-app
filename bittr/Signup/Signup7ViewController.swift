//
//  Signup7ViewController.swift
//  bittr
//
//  Created by Tom Melters on 02/06/2023.
//

import UIKit

class Signup7ViewController: UIViewController {

    // Confirmation of created wallet. Sign up with bittr or skip directly to wallet.
    
    @IBOutlet weak var checkView: UIView!
    @IBOutlet weak var saveView: UIView!
    @IBOutlet weak var nextButton: UIButton!
    @IBOutlet weak var skipButton: UIButton!
    @IBOutlet weak var cardView: UIView!
    @IBOutlet weak var imageContainer: UIView!
    
    // Article elements.
    @IBOutlet weak var articleButton: UIButton!
    @IBOutlet weak var spinner1: UIActivityIndicatorView!
    @IBOutlet weak var articleImage: UIImageView!
    @IBOutlet weak var articleTitle: UILabel!
    let pageArticle1Slug = "what-is-bittr"
    var pageArticle1 = Article()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Corner radii and button items.
        checkView.layer.cornerRadius = 35
        saveView.layer.cornerRadius = 13
        cardView.layer.cornerRadius = 13
        imageContainer.layer.cornerRadius = 13
        nextButton.setTitle("", for: .normal)
        skipButton.setTitle("", for: .normal)
        articleButton.setTitle("", for: .normal)
        
        // Check view elements.
        let viewBorder = CAShapeLayer()
        viewBorder.strokeColor = UIColor.black.cgColor
        viewBorder.frame = checkView.bounds
        viewBorder.fillColor = nil
        viewBorder.path = UIBezierPath(roundedRect: checkView.bounds, cornerRadius: 35).cgPath
        viewBorder.lineWidth = 2
        self.checkView.layer.addSublayer(viewBorder)
        
        // Notification observers.
        NotificationCenter.default.addObserver(self, selector: #selector(setSignupArticles), name: NSNotification.Name(rawValue: "setsignuparticles"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(setArticleImage), name: NSNotification.Name(rawValue: "setimage\(pageArticle1Slug)"), object: nil)
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
    
    
    @IBAction func skipButtonTapped(_ sender: UIButton) {
        
        // Close sign up and proceed into wallet.
        NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "restorewallet"), object: nil, userInfo: nil) as Notification)
    }
    
    @IBAction func nextButtonTapped(_ sender: UIButton) {
        
        // Proceed to bittr signup.
        let notificationDict:[String: Any] = ["page":sender.accessibilityIdentifier]
        NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "signupnext"), object: nil, userInfo: notificationDict) as Notification)
    }
    
    @IBAction func articleButtonTapped(_ sender: UIButton) {
        
        let notificationDict:[String: Any] = ["tag":sender.accessibilityIdentifier]
        
        NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "launcharticle"), object: nil, userInfo: notificationDict) as Notification)
    }
    
}
