//
//  Signup1ViewController.swift
//  bittr
//
//  Created by Tom Melters on 22/05/2023.
//

import UIKit

class Signup1ViewController: UIViewController {

    @IBOutlet weak var headerView: UIView!
    @IBOutlet weak var buttonView: UIView!
    @IBOutlet weak var nextButton: UIButton!
    @IBOutlet weak var restoreView: UIView!
    @IBOutlet weak var restoreButton: UIButton!
    @IBOutlet weak var cardView: UIView!
    @IBOutlet weak var imageContainer: UIView!
    @IBOutlet weak var articleButton: UIButton!
    
    override func viewDidLoad() {
        super.viewDidLoad()

        headerView.layer.cornerRadius = 13
        buttonView.layer.cornerRadius = 13
        restoreView.layer.cornerRadius = 13
        cardView.layer.cornerRadius = 13
        imageContainer.layer.cornerRadius = 13
        nextButton.setTitle("", for: .normal)
        restoreButton.setTitle("", for: .normal)
        articleButton.setTitle("", for: .normal)
        
        cardView.layer.shadowColor = UIColor.black.cgColor
        cardView.layer.shadowOffset = CGSize(width: 0, height: 8)
        cardView.layer.shadowRadius = 12.0
        cardView.layer.shadowOpacity = 0.05
    }
    

    @IBAction func restoreButtonClicked(_ sender: UIButton) {
        
        let notificationDict:[String: Any] = ["page":sender.accessibilityIdentifier]
        NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "signupnext"), object: nil, userInfo: notificationDict) as Notification)
    }
    
    @IBAction func nextButtonTapped(_ sender: UIButton) {
        
        let notificationDict:[String: Any] = ["page":sender.accessibilityIdentifier]
        NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "signupnext"), object: nil, userInfo: notificationDict) as Notification)
    }
    
    @IBAction func articleButtonTapped(_ sender: UIButton) {
        let notificationDict:[String: Any] = ["tag":sender.tag]
        NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "launcharticle"), object: nil, userInfo: notificationDict) as Notification)
    }
    
}
