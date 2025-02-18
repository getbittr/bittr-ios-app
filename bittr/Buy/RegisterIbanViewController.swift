//
//  RegisterIbanViewController.swift
//  bittr
//
//  Created by Tom Melters on 15/06/2023.
//

import UIKit

class RegisterIbanViewController: UIViewController {
    
    @IBOutlet weak var downButton: UIButton!
    var currentPage = 0
    
    @IBOutlet weak var signup7ContainerViewLeading: NSLayoutConstraint!
    
    var currentClientID = ""
    var articles:[String:Article]?
    var allImages:[String:UIImage]?
    var coreVC:CoreViewController?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        downButton.setTitle("", for: .normal)
        
        NotificationCenter.default.addObserver(self, selector: #selector(nextPageTapped), name: NSNotification.Name(rawValue: "signupnext"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(downButtonTapped), name: NSNotification.Name(rawValue: "restorewallet"), object: nil)
        
        self.changeColors()
    }
    
    @objc func nextPageTapped(notification:NSNotification) {
        
        if let userInfo = notification.userInfo as [AnyHashable:Any]? {
            if let pageNumber = userInfo["page"] as? String {
                
                let viewWidth = self.view.safeAreaLayoutGuide.layoutFrame.size.width
                var leadingConstant:CGFloat = 0
                
                switch pageNumber {
                case "6":
                    leadingConstant = -1 * viewWidth
                    currentPage = 8
                case "7":
                    leadingConstant = -1 * viewWidth
                    currentPage = 9
                case "8":
                    leadingConstant = -2 * viewWidth
                    currentPage = 10
                case "9":
                    leadingConstant = -3 * viewWidth
                    currentPage = 11
                default:
                    leadingConstant = -viewWidth
                }
                
                UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseInOut) {
                    
                    self.signup7ContainerViewLeading.constant = leadingConstant
                    self.view.layoutIfNeeded()
                }
            }
        }
    }
    
    @IBAction func downButtonTapped(_ sender: UIButton) {
        
        self.dismiss(animated: true, completion: nil)
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        
        if segue.identifier == "RegisterToSignup7" {
            
            if let signup7VC = segue.destination as? Signup7ViewController {
                signup7VC.embeddedInBuyVC = true
                signup7VC.coreVC = self.coreVC
            }
        } else if segue.identifier == "RegisterToTransfer1" {
            
            let transfer1VC = segue.destination as? Transfer1ViewController
            if let actualTransfer1VC = transfer1VC {
                
                actualTransfer1VC.currentClientID = self.currentClientID
                actualTransfer1VC.articles = self.articles
                actualTransfer1VC.allImages = self.allImages
                actualTransfer1VC.coreVC = self.coreVC
            }
        } else if segue.identifier == "RegisterToTransfer2" {
            
            let transfer2VC = segue.destination as? Transfer2ViewController
            if let actualTransfer2VC = transfer2VC {
                
                actualTransfer2VC.articles = self.articles
                actualTransfer2VC.allImages = self.allImages
                actualTransfer2VC.coreVC = self.coreVC
            }
        } else if segue.identifier == "RegisterToTransfer3" {
            
            let transfer3VC = segue.destination as? Transfer3ViewController
            if let actualTransfer3VC = transfer3VC {
                
                actualTransfer3VC.articles = self.articles
                actualTransfer3VC.allImages = self.allImages
                actualTransfer3VC.coreVC = self.coreVC
            }
        }
    }
    
    func changeColors() {
        
        self.view.backgroundColor = Colors.getColor("yelloworblue1")
    }
    
}
