//
//  SignupViewController.swift
//  bittr
//
//  Created by Tom Melters on 22/05/2023.
//

import UIKit

class SignupViewController: UIViewController {

    // View that contains the container views of all signup views.
    
    @IBOutlet weak var signup1ContainerViewLeading: NSLayoutConstraint!
    var currentPage = 0
    var coreVC:CoreViewController?
    
    override func viewDidLoad() {
        super.viewDidLoad()

        NotificationCenter.default.addObserver(self, selector: #selector(nextPageTapped), name: NSNotification.Name(rawValue: "signupnext"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(screenshotTaken), name: UIApplication.userDidTakeScreenshotNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(changeColors), name: NSNotification.Name(rawValue: "changecolors"), object: nil)

        self.changeColors()
    }
    
    @objc func nextPageTapped(notification:NSNotification) {
        
        // Check internet connection.
        if !Reachability.isConnectedToNetwork() {
            // User not connected to internet.
            self.showAlert(Language.getWord(withID: "checkyourconnection"), Language.getWord(withID: "trytoconnect"), Language.getWord(withID: "okay"))
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
    }
    
    @objc func screenshotTaken() {
        // User shouldn't screenshot their mnemonic.
        if currentPage == 3 {
            self.showAlert(Language.getWord(withID: "becareful"), Language.getWord(withID: "noscreenshot"), Language.getWord(withID: "okay"))
        }
    }
    
    @IBAction func articleButtonTapped(_ sender: UIButton) {
        
        // Open article.
        let notificationDict:[String: Any] = ["tag":sender.tag]
        NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "launcharticle"), object: nil, userInfo: notificationDict) as Notification)
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        
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
    }
    
    @objc func changeColors() {
        
        self.view.backgroundColor = Colors.getColor("yelloworblue1")
    }
    
}
