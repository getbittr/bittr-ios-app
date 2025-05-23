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
    var currentClientID = ""
    var currentIbanID = ""
    var currentCode = false
    var animateTransition = true
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.allContainerViews = [self.secondRestorePinContainer, self.firstRestorePinContainer, self.restoreMnemonicContainer, self.createWalletContainer, self.createWalletCheckContainer, self.newMnemonicContainer, self.newMnemonicCheckContainer, self.firstPinContainer, self.secondPinContainer, self.walletReadyContainer, self.bittrSignupContainer, self.bittrEmailVerificationContainer, self.bittrDetailsContainer, self.bittrFinalContainer]

        //NotificationCenter.default.addObserver(self, selector: #selector(nextPageTapped), name: NSNotification.Name(rawValue: "signupnext"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(screenshotTaken), name: UIApplication.userDidTakeScreenshotNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(changeColors), name: NSNotification.Name(rawValue: "changecolors"), object: nil)

        self.changeColors()
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
        
        // Set SignupVC for embedding view controller.
        (newChild as? Restore3ViewController)?.signupVC = self
        (newChild as? Restore2ViewController)?.signupVC = self
        (newChild as? RestoreViewController)?.signupVC = self
        (newChild as? Signup1ViewController)?.signupVC = self
        (newChild as? Signup2ViewController)?.signupVC = self
        (newChild as? Signup3ViewController)?.signupVC = self
        (newChild as? Signup4ViewController)?.signupVC = self
        (newChild as? Signup5ViewController)?.signupVC = self
        (newChild as? Signup6ViewController)?.signupVC = self
        (newChild as? Signup7ViewController)?.signupVC = self
        (newChild as? Transfer1ViewController)?.signupVC = self
        (newChild as? Transfer15ViewController)?.signupVC = self
        (newChild as? Transfer2ViewController)?.signupVC = self
        (newChild as? Transfer3ViewController)?.signupVC = self
        
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
    
    /*@objc func nextPageTapped(notification:NSNotification) {
        
        // Check internet connection.
        if !Reachability.isConnectedToNetwork() {
            // User not connected to internet.
            self.showAlert(presentingController: self, title: Language.getWord(withID: "checkyourconnection"), message: Language.getWord(withID: "trytoconnect"), buttons: [Language.getWord(withID: "okay")], actions: nil)
            return
        }
        
        if let userInfo = notification.userInfo as [AnyHashable:Any]? {
            if let pageNumber = userInfo["page"] as? String {
                
                let viewWidth = self.view.safeAreaLayoutGuide.layoutFrame.size.width
                var leadingConstant:CGFloat = 0
                
                switch pageNumber {
                case "restore":
                    leadingConstant = 0
                    currentPage = -1
                case "-3":
                    leadingConstant = 2 * viewWidth
                    currentPage = -2
                case "-4":
                    leadingConstant = 3 * viewWidth
                    currentPage = -3
                case "-1":
                    leadingConstant = viewWidth
                    currentPage = 1
                case "0":
                    leadingConstant = -viewWidth
                    currentPage = 2
                case "1":
                    leadingConstant = -2 * viewWidth
                    currentPage = 3
                case "2":
                    leadingConstant = -3 * viewWidth
                    currentPage = 4
                case "3":
                    leadingConstant = -4 * viewWidth
                    currentPage = 5
                case "4":
                    leadingConstant = -5 * viewWidth
                    currentPage = 6
                case "5":
                    leadingConstant = -6 * viewWidth
                    currentPage = 7
                case "6":
                    leadingConstant = -7 * viewWidth
                    currentPage = 8
                case "7":
                    leadingConstant = -8 * viewWidth
                    currentPage = 9
                case "8":
                    leadingConstant = -9 * viewWidth
                    currentPage = 10
                case "9":
                    leadingConstant = -10 * viewWidth
                    currentPage = 11
                default:
                    leadingConstant = -viewWidth
                }
                
                // Animate slide to next page.
                UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseInOut) {
                    self.signup1ContainerViewLeading.constant = leadingConstant
                    self.view.layoutIfNeeded()
                }
                
                // Individual page checks.
                if pageNumber == "9" {
                    NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "checkimagedownload"), object: nil, userInfo: nil) as Notification)
                }
            }
        }
    }*/
    
    @objc func screenshotTaken() {
        // User shouldn't screenshot their mnemonic.
        if self.currentPage == 5 {
            self.showAlert(presentingController: self, title: Language.getWord(withID: "becareful"), message: Language.getWord(withID: "noscreenshot"), buttons: [Language.getWord(withID: "okay")], actions: nil)
        }
    }
    
    @IBAction func articleButtonTapped(_ sender: UIButton) {
        
        // Open article.
        let notificationDict:[String: Any] = ["tag":sender.tag]
        NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "launcharticle"), object: nil, userInfo: notificationDict) as Notification)
    }
    
    /*override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        
        switch segue.identifier {
        case "SignupToSignup1":
            if let thisVC = segue.destination as? Signup1ViewController {thisVC.coreVC = self.coreVC}
        case "SignupToSignup2":
            if let thisVC = segue.destination as? Signup2ViewController {thisVC.coreVC = self.coreVC}
        case "SignupToSignup3":
            if let thisVC = segue.destination as? Signup3ViewController {thisVC.coreVC = self.coreVC}
        case "SignupToSignup4":
            if let thisVC = segue.destination as? Signup4ViewController {thisVC.coreVC = self.coreVC}
        case "SignupToSignup5":
            if let thisVC = segue.destination as? Signup5ViewController {thisVC.coreVC = self.coreVC}
        case "SignupToSignup6":
            if let thisVC = segue.destination as? Signup6ViewController {thisVC.coreVC = self.coreVC}
        case "SignupToSignup7":
            if let thisVC = segue.destination as? Signup7ViewController {thisVC.coreVC = self.coreVC}
        case "SignupToTransfer1":
            if let thisVC = segue.destination as? Transfer1ViewController {thisVC.coreVC = self.coreVC}
        case "SignupToTransfer15":
            if let thisVC = segue.destination as? Transfer15ViewController {thisVC.coreVC = self.coreVC}
        case "SignupToTransfer2":
            if let thisVC = segue.destination as? Transfer2ViewController {thisVC.coreVC = self.coreVC}
        case "SignupToTransfer3":
            if let thisVC = segue.destination as? Transfer3ViewController {thisVC.coreVC = self.coreVC}
        case "SignupToRestore":
            if let thisVC = segue.destination as? RestoreViewController {thisVC.coreVC = self.coreVC}
        case "SignupToRestore2":
            if let thisVC = segue.destination as? Restore2ViewController {thisVC.coreVC = self.coreVC}
        case "SignupToRestore3":
            if let thisVC = segue.destination as? Restore3ViewController {thisVC.coreVC = self.coreVC}
        default:
            if let thisVC = segue.destination as? Signup1ViewController {thisVC.coreVC = self.coreVC}
        }
    }*/
    
    @objc func changeColors() {
        self.view.backgroundColor = Colors.getColor("yelloworblue1")
    }
    
}
