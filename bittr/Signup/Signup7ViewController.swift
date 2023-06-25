//
//  Signup7ViewController.swift
//  bittr
//
//  Created by Tom Melters on 02/06/2023.
//

import UIKit

class Signup7ViewController: UIViewController {

    @IBOutlet weak var checkView: UIView!
    @IBOutlet weak var saveView: UIView!
    @IBOutlet weak var nextButton: UIButton!
    @IBOutlet weak var skipButton: UIButton!
    @IBOutlet weak var cardView: UIView!
    @IBOutlet weak var imageContainer: UIView!
    @IBOutlet weak var articleButton: UIButton!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        checkView.layer.cornerRadius = 35
        saveView.layer.cornerRadius = 13
        cardView.layer.cornerRadius = 13
        imageContainer.layer.cornerRadius = 13
        nextButton.setTitle("", for: .normal)
        skipButton.setTitle("", for: .normal)
        articleButton.setTitle("", for: .normal)
        
        let viewBorder = CAShapeLayer()
        viewBorder.strokeColor = UIColor.black.cgColor
        viewBorder.frame = checkView.bounds
        viewBorder.fillColor = nil
        viewBorder.path = UIBezierPath(roundedRect: checkView.bounds, cornerRadius: 35).cgPath
        viewBorder.lineWidth = 2
        self.checkView.layer.addSublayer(viewBorder)
    }
    
    
    @IBAction func skipButtonTapped(_ sender: UIButton) {
        
        NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "restorewallet"), object: nil, userInfo: nil) as Notification)
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
