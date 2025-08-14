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
    @IBOutlet weak var signup7ContainerViewLeading: NSLayoutConstraint!
    
    // Variables
    var coreVC:CoreViewController?
    var currentPage = 0
    var transfer1VC: Transfer1ViewController?
    var transfer15VC: Transfer15ViewController?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Button titles
        self.downButton.setTitle("", for: .normal)
        
        // Set colors
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
                transfer1VC.coreVC = self.coreVC
                transfer1VC.ibanVC = self
                self.transfer1VC = transfer1VC
            }
        } else if segue.identifier == "RegisterToTransfer15" {
            if let transfer15VC = segue.destination as? Transfer15ViewController {
                transfer15VC.coreVC = self.coreVC
                transfer15VC.ibanVC = self
                self.transfer15VC = transfer15VC
            }
        } else if segue.identifier == "RegisterToTransfer2" {
            if let transfer2VC = segue.destination as? Transfer2ViewController {
                transfer2VC.coreVC = self.coreVC
                transfer2VC.ibanVC = self
            }
        } else if segue.identifier == "RegisterToTransfer3" {
            if let transfer3VC = segue.destination as? Transfer3ViewController {
                transfer3VC.coreVC = self.coreVC
                transfer3VC.ibanVC = self
            }
        }
    }
    
    func changeColors() {
        
        self.view.backgroundColor = Colors.getColor("yelloworblue1")
    }
    
}
