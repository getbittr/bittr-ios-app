//
//  Transfer3ViewController.swift
//  bittr
//
//  Created by Tom Melters on 11/06/2023.
//

import UIKit

class Transfer3ViewController: UIViewController {

    @IBOutlet weak var headerView: UIView!
    @IBOutlet weak var nextView: UIView!
    @IBOutlet weak var nextButton: UIButton!
    @IBOutlet weak var cardView: UIView!
    @IBOutlet weak var imageContainer: UIView!
    @IBOutlet weak var cardView2: UIView!
    @IBOutlet weak var imageContainer2: UIView!
    @IBOutlet weak var articleButton: UIButton!
    @IBOutlet weak var articleButton2: UIButton!
    @IBOutlet weak var backButton: UIButton!
    
    override func viewDidLoad() {
        super.viewDidLoad()

        headerView.layer.cornerRadius = 13
        nextView.layer.cornerRadius = 13
        cardView.layer.cornerRadius = 13
        imageContainer.layer.cornerRadius = 13
        cardView2.layer.cornerRadius = 13
        imageContainer2.layer.cornerRadius = 13
        
        nextButton.setTitle("", for: .normal)
        articleButton.setTitle("", for: .normal)
        articleButton2.setTitle("", for: .normal)
        backButton.setTitle("", for: .normal)
    }
    
    @IBAction func nextButtonTapped(_ sender: UIButton) {
        
        let alert = UIAlertController(title: "Open your banking app", message: "\nCreate your (recurring) transfer to\n\nNL12 INGB 1234 5678 90\nBITTR AG\n1234567890", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Done", style: .cancel, handler: {_ in
            NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "restorewallet"), object: nil, userInfo: nil) as Notification)
        }))
        self.present(alert, animated: true)
    }
    
    @IBAction func articleButtonTapped(_ sender: UIButton) {
        
        let notificationDict:[String: Any] = ["tag":sender.tag]
        
        NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "launcharticle"), object: nil, userInfo: notificationDict) as Notification)
    }
    
    @IBAction func backButtonTapped(_ sender: UIButton) {
        
        let notificationDict:[String: Any] = ["page":sender.accessibilityIdentifier]
         NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "signupnext"), object: nil, userInfo: notificationDict) as Notification)
    }
    
}
