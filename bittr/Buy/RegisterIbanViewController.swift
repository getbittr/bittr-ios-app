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
        
        // Button titles
        self.downButton.setTitle("", for: .normal)
        
        NotificationCenter.default.addObserver(self, selector: #selector(downButtonTapped), name: NSNotification.Name(rawValue: "restorewallet"), object: nil)
        
        self.changeColors()
    }
    
    func moveToPage(_ thisPage:Int) {
        
        // Check internet connection.
        if !Reachability.isConnectedToNetwork() {
            // User not connected to internet.
            self.showAlert(presentingController: self, title: Language.getWord(withID: "checkyourconnection"), message: Language.getWord(withID: "trytoconnect"), buttons: [Language.getWord(withID: "okay")], actions: nil)
            return
        }
        
        let navigateToPage = thisPage - 9
        let viewWidth = self.view.safeAreaLayoutGuide.layoutFrame.size.width
        
        UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseInOut) {
            self.signup7ContainerViewLeading.constant = -viewWidth*CGFloat(navigateToPage)
            self.view.layoutIfNeeded()
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
                signup7VC.ibanVC = self
            }
        } else if segue.identifier == "RegisterToTransfer1" {
            if let transfer1VC = segue.destination as? Transfer1ViewController {
                transfer1VC.currentClientID = self.currentClientID
                transfer1VC.articles = self.articles
                transfer1VC.allImages = self.allImages
                transfer1VC.coreVC = self.coreVC
                transfer1VC.ibanVC = self
            }
        } else if segue.identifier == "RegisterToTransfer15" {
            if let transfer15VC = segue.destination as? Transfer15ViewController {
                transfer15VC.coreVC = self.coreVC
                transfer15VC.ibanVC = self
            }
        } else if segue.identifier == "RegisterToTransfer2" {
            if let transfer2VC = segue.destination as? Transfer2ViewController {
                transfer2VC.articles = self.articles
                transfer2VC.allImages = self.allImages
                transfer2VC.coreVC = self.coreVC
                transfer2VC.ibanVC = self
            }
        } else if segue.identifier == "RegisterToTransfer3" {
            if let transfer3VC = segue.destination as? Transfer3ViewController {
                transfer3VC.articles = self.articles
                transfer3VC.allImages = self.allImages
                transfer3VC.coreVC = self.coreVC
                transfer3VC.ibanVC = self
            }
        }
    }
    
    func changeColors() {
        
        self.view.backgroundColor = Colors.getColor("yelloworblue1")
    }
    
}
