//
//  RegisterIbanViewController.swift
//  bittr
//
//  Created by Tom Melters on 15/06/2023.
//

import UIKit

class RegisterIbanViewController: UIViewController {
    
    // UI elements
    @IBOutlet weak var downButton: UIButton!
    
    // Container views
    @IBOutlet weak var walletReadyContainer: UIView!
    @IBOutlet weak var bittrSignupContainer: UIView!
    @IBOutlet weak var bittrEmailVerificationContainer: UIView!
    @IBOutlet weak var bittrDetailsContainer: UIView!
    @IBOutlet weak var bittrFinalContainer: UIView!
    
    // Leading constraint
    @IBOutlet weak var containerViewsLeading: NSLayoutConstraint!
    
    // Variables
    var coreVC:CoreViewController?
    var currentPage = 0
    var transfer1VC: Transfer1ViewController?
    var transfer15VC: Transfer15ViewController?
    var currentIbanID = ""
    var allContainerViews = [UIView]()
    var embedViewIdentifiers = ["Signup7", "Transfer1", "Transfer15", "Transfer2", "Transfer3"]
    var animateTransition = true
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Button titles
        self.downButton.setTitle("", for: .normal)
        
        // Set colors
        self.changeColors()
        
        // Container views
        self.allContainerViews = [self.walletReadyContainer, self.bittrSignupContainer, self.bittrEmailVerificationContainer, self.bittrDetailsContainer, self.bittrFinalContainer]
        self.animateTransition = false
        self.moveToPage(0)
    }
    
    func moveToPage(_ thisPage:Int) {
        
        // Check internet connection.
        if !Reachability.isConnectedToNetwork() {
            // User not connected to internet.
            self.showAlert(presentingController: self, title: Language.getWord(withID: "checkyourconnection"), message: Language.getWord(withID: "trytoconnect"), buttons: [Language.getWord(withID: "okay")], actions: nil)
            return
        }
        
        // Identify new view controller.
        let storyboard = UIStoryboard(name: "Main", bundle: Bundle.main)
        let newChild = storyboard.instantiateViewController(withIdentifier: self.embedViewIdentifiers[thisPage])
        
        (newChild as? Signup7ViewController)?.ibanVC = self
        (newChild as? Signup7ViewController)?.coreVC = self.coreVC
        
        (newChild as? Transfer1ViewController)?.ibanVC = self
        (newChild as? Transfer1ViewController)?.coreVC = self.coreVC
        
        (newChild as? Transfer15ViewController)?.ibanVC = self
        (newChild as? Transfer15ViewController)?.coreVC = self.coreVC
        
        (newChild as? Transfer2ViewController)?.ibanVC = self
        (newChild as? Transfer2ViewController)?.coreVC = self.coreVC
        
        (newChild as? Transfer3ViewController)?.ibanVC = self
        (newChild as? Transfer3ViewController)?.coreVC = self.coreVC
        
        // Add new view controller to correct container view.
        self.addChild(newChild)
        newChild.view.frame.size = self.allContainerViews[thisPage].frame.size
        self.allContainerViews[thisPage].addSubview(newChild.view)
        newChild.didMove(toParent: self)
        
        // Update current page
        self.currentPage = thisPage
        
        // Animate slide to next page
        var duration = 0.3
        if !self.animateTransition {
            duration = 0
        }
        UIView.animate(withDuration: duration, delay: 0, options: .curveEaseInOut) {
            self.containerViewsLeading.constant = UIScreen.main.bounds.width * CGFloat(-thisPage)
            self.view.layoutIfNeeded()
        } completion: { _ in
            
            // Remove previous view from its container.
            for (index, eachContainer) in self.allContainerViews.enumerated() {
                if index != thisPage, eachContainer.subviews.count > 0 {
                    for eachSubview in eachContainer.subviews {
                        eachSubview.removeFromSuperview()
                    }
                }
            }
            self.animateTransition = true
        }
    }
    
    @IBAction func downButtonTapped(_ sender: UIButton) {
        
        self.dismiss(animated: true, completion: nil)
    }
    
    func changeColors() {
        
        self.view.backgroundColor = Colors.getColor("yelloworblue1")
    }
    
}
