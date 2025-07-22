//
//  SignupViewController.swift
//  bittr
//
//  Created by Tom Melters on 22/05/2023.
//

import UIKit

class SignupViewController: UIViewController {

    // View that contains the container views of all signup views.
    
    // Container views
    @IBOutlet weak var secondRestorePinContainer: UIView!
    @IBOutlet weak var firstRestorePinContainer: UIView!
    @IBOutlet weak var restoreMnemonicContainer: UIView!
    @IBOutlet weak var createWalletContainer: UIView!
    @IBOutlet weak var createWalletCheckContainer: UIView!
    @IBOutlet weak var newMnemonicContainer: UIView!
    @IBOutlet weak var newMnemonicCheckContainer: UIView!
    @IBOutlet weak var firstPinContainer: UIView!
    @IBOutlet weak var secondPinContainer: UIView!
    @IBOutlet weak var walletReadyContainer: UIView!
    @IBOutlet weak var bittrSignupContainer: UIView!
    @IBOutlet weak var bittrEmailVerificationContainer: UIView!
    @IBOutlet weak var bittrDetailsContainer: UIView!
    @IBOutlet weak var bittrFinalContainer: UIView!
    
    // Leading constraint
    @IBOutlet weak var containerViewsLeading: NSLayoutConstraint!
    
    // Variables
    var currentPage = 0
    var coreVC:CoreViewController?
    var allContainerViews = [UIView]()
    var embedViewIdentifiers = ["Restore3", "Restore2", "Restore", "Signup1", "Signup2", "Signup3", "Signup4", "Signup5", "Signup6", "Signup7", "Transfer1", "Transfer15", "Transfer2", "Transfer"]
    var enteredPin = ""
    var currentIbanID = ""
    var currentCode = false
    var animateTransition = true
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.allContainerViews = [self.secondRestorePinContainer, self.firstRestorePinContainer, self.restoreMnemonicContainer, self.createWalletContainer, self.createWalletCheckContainer, self.newMnemonicContainer, self.newMnemonicCheckContainer, self.firstPinContainer, self.secondPinContainer, self.walletReadyContainer, self.bittrSignupContainer, self.bittrEmailVerificationContainer, self.bittrDetailsContainer, self.bittrFinalContainer]

        NotificationCenter.default.addObserver(self, selector: #selector(screenshotTaken), name: UIApplication.userDidTakeScreenshotNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(changeColors), name: NSNotification.Name(rawValue: "changecolors"), object: nil)

        self.changeColors()
    }
    
    func moveToPage(_ thisPage:Int) {
        
        // SECURITY: Prevent access to sensitive pages during PIN reset
        if self.coreVC?.resettingPin == true {
            // During PIN reset, only allow access to restore-related pages (0, 1, 2)
            // Block access to mnemonic display pages (3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13)
            if thisPage > 2 {
                print("SECURITY: Blocked access to page \(thisPage) during PIN reset")
                self.showAlert(
                    presentingController: self,
                    title: "Access Restricted",
                    message: "This option is not available during PIN reset for security reasons.",
                    buttons: ["OK"],
                    actions: nil
                )
                return
            }
        }
        
        // Check internet connection.
        if !Reachability.isConnectedToNetwork() {
            // User not connected to internet.
            self.showAlert(presentingController: self, title: Language.getWord(withID: "checkyourconnection"), message: Language.getWord(withID: "trytoconnect"), buttons: [Language.getWord(withID: "okay")], actions: nil)
            return
        }
        
        // Identify new view controller.
        let storyboard = UIStoryboard(name: "Main", bundle: Bundle.main)
        let newChild = storyboard.instantiateViewController(withIdentifier: self.embedViewIdentifiers[thisPage])
        
        // Set SignupVC and CoreVC for embedding view controller.
        (newChild as? Restore3ViewController)?.signupVC = self
        (newChild as? Restore3ViewController)?.coreVC = self.coreVC
        
        (newChild as? Restore2ViewController)?.signupVC = self
        (newChild as? Restore2ViewController)?.coreVC = self.coreVC
        
        (newChild as? RestoreViewController)?.signupVC = self
        (newChild as? RestoreViewController)?.coreVC = self.coreVC
        
        (newChild as? Signup1ViewController)?.signupVC = self
        (newChild as? Signup1ViewController)?.coreVC = self.coreVC
        
        (newChild as? Signup2ViewController)?.signupVC = self
        (newChild as? Signup2ViewController)?.coreVC = self.coreVC
        
        (newChild as? Signup3ViewController)?.signupVC = self
        (newChild as? Signup3ViewController)?.coreVC = self.coreVC
        
        (newChild as? Signup4ViewController)?.signupVC = self
        (newChild as? Signup4ViewController)?.coreVC = self.coreVC
        
        (newChild as? Signup5ViewController)?.signupVC = self
        (newChild as? Signup5ViewController)?.coreVC = self.coreVC
        
        (newChild as? Signup6ViewController)?.signupVC = self
        (newChild as? Signup6ViewController)?.coreVC = self.coreVC
        
        (newChild as? Signup7ViewController)?.signupVC = self
        (newChild as? Signup7ViewController)?.coreVC = self.coreVC
        
        (newChild as? Transfer1ViewController)?.signupVC = self
        (newChild as? Transfer1ViewController)?.coreVC = self.coreVC
        
        (newChild as? Transfer15ViewController)?.signupVC = self
        (newChild as? Transfer15ViewController)?.coreVC = self.coreVC
        
        (newChild as? Transfer2ViewController)?.signupVC = self
        (newChild as? Transfer2ViewController)?.coreVC = self.coreVC
        
        (newChild as? Transfer3ViewController)?.signupVC = self
        (newChild as? Transfer3ViewController)?.coreVC = self.coreVC
        
        // Add new view controller to correct container view.
        self.addChild(newChild)
        newChild.view.frame.size = self.allContainerViews[thisPage].frame.size
        self.allContainerViews[thisPage].addSubview(newChild.view)
        newChild.didMove(toParent: self)
        
        // Update current page
        self.currentPage = thisPage
        
        // SECURITY: Hide sensitive containers during PIN reset
        if self.coreVC?.resettingPin == true {
            // Hide create wallet containers during PIN reset
            self.createWalletContainer.alpha = 0
            self.createWalletCheckContainer.alpha = 0
        } else {
            // Show create wallet containers during normal flow
            self.createWalletContainer.alpha = 1
            self.createWalletCheckContainer.alpha = 1
        }
        
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
    
    @objc func screenshotTaken() {
        // User shouldn't screenshot their mnemonic.
        if self.currentPage == 5 {
            self.showAlert(presentingController: self, title: Language.getWord(withID: "becareful"), message: Language.getWord(withID: "noscreenshot"), buttons: [Language.getWord(withID: "okay")], actions: nil)
        }
    }
    
    @objc func changeColors() {
        self.view.backgroundColor = Colors.getColor("yelloworblue1")
    }
    
}
