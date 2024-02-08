//
//  PinViewController.swift
//  bittr
//
//  Created by Tom Melters on 29/08/2023.
//

import UIKit
import KeychainSwift

class PinViewController: UIViewController, UITextFieldDelegate {

    @IBOutlet weak var pinScrollView: UIScrollView!
    @IBOutlet weak var pinContentView: UIView!
    @IBOutlet weak var pinCenterView: UIView!
    @IBOutlet weak var confirmPinView: UIView!
    @IBOutlet weak var confirmPinButton: UIButton!
    @IBOutlet weak var restoreWalletButton: UIButton!
    @IBOutlet weak var centerViewCenterY: NSLayoutConstraint!
    @IBOutlet weak var contentViewHeight: NSLayoutConstraint!
    
    @IBOutlet weak var button1: UIButton!
    @IBOutlet weak var button2: UIButton!
    @IBOutlet weak var button3: UIButton!
    @IBOutlet weak var button4: UIButton!
    @IBOutlet weak var button5: UIButton!
    @IBOutlet weak var button6: UIButton!
    @IBOutlet weak var button7: UIButton!
    @IBOutlet weak var button8: UIButton!
    @IBOutlet weak var button9: UIButton!
    @IBOutlet weak var button0: UIButton!
    @IBOutlet weak var buttonBackspace: UIButton!
    @IBOutlet weak var pinTextField: UITextField!
    @IBOutlet weak var pinSpinner: UIActivityIndicatorView!
    
    var correctPin:String?
    
    var coreVC:CoreViewController?
    
    override func viewDidLoad() {
        super.viewDidLoad()

        confirmPinView.layer.cornerRadius = 13
        
        confirmPinButton.setTitle("", for: .normal)
        restoreWalletButton.setTitle("", for: .normal)
        button1.setTitle("", for: .normal)
        button2.setTitle("", for: .normal)
        button3.setTitle("", for: .normal)
        button4.setTitle("", for: .normal)
        button5.setTitle("", for: .normal)
        button6.setTitle("", for: .normal)
        button7.setTitle("", for: .normal)
        button8.setTitle("", for: .normal)
        button9.setTitle("", for: .normal)
        button0.setTitle("", for: .normal)
        buttonBackspace.setTitle("", for: .normal)
        
        pinTextField.delegate = self
        
        if CacheManager.getPin() != "empty" {
            self.correctPin = CacheManager.getPin()
        } else {
            // Migration away from Keychain.
            let keychain = KeychainSwift()
            keychain.synchronizable = true
            if keychain.get("pin") != nil {
                self.correctPin = keychain.get("pin")
                CacheManager.storePin(pin: self.correctPin!)
                keychain.delete("pin")
            }
        }
    }
    
    @IBAction func numberButtonTapped(_ sender: UIButton) {
        
        pinTextField.insertText(String(sender.tag))
    }
    
    @IBAction func backspaceButtonTapped(_ sender: UIButton) {
        
        pinTextField.deleteBackward()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        
        let centerViewHeight = pinCenterView.bounds.height
        
        if pinCenterView.bounds.height + 40 > pinContentView.bounds.height {
            
            NSLayoutConstraint.deactivate([self.contentViewHeight])
            self.contentViewHeight = NSLayoutConstraint(item: self.pinContentView, attribute: .height, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: centerViewHeight)
            NSLayoutConstraint.activate([self.contentViewHeight])
            self.centerViewCenterY.constant = 0
            self.view.layoutIfNeeded()
        }
    }
    
    @IBAction func confirmPinButtonTapped(_ sender: UIButton) {
        
        // Check internet connection.
        if !Reachability.isConnectedToNetwork() {
            // User not connected to internet.
            let alert = UIAlertController(title: "Check your connection", message: "You don't seem to be connected to the internet. Please try to connect.", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Okay", style: .cancel, handler: nil))
            self.present(alert, animated: true)
            return
        }
        
        if let actualCorrectPin = self.correctPin {
            
            if actualCorrectPin == self.pinTextField.text {
                // Correct pin.
                if let actualCoreVC = self.coreVC {
                    
                    self.pinSpinner.startAnimating()
                    
                    // Step 1.
                    actualCoreVC.correctPin(spinner:self.pinSpinner)
                }
            } else {
                // Wrong pin.
                let alert = UIAlertController(title: "Incorrect PIN", message: "Please enter your correct pin. If you've forgotten it, please restore your wallet.", preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "Okay", style: .cancel, handler: nil))
                self.present(alert, animated: true)
            }
        } else {
            // No pin found in storage.
        }
    }
    
    @IBAction func restoreButtonTapped(_ sender: UIButton) {
        
        let alert = UIAlertController(title: "Restore wallet", message: "\nThis app only supports one wallet simultaneously. Restoring a wallet means removing this current wallet from your device.\n\nOnly restore a wallet if you're sure you've properly backed up this current wallet.", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        alert.addAction(UIAlertAction(title: "Restore", style: .destructive, handler: {_ in
            
            let secondAlert = UIAlertController(title: "Restore wallet", message: "\nAre you sure you want to remove this current wallet from your device and replace it with a restored one?\n\nIf you tap Restore, we'll reset and close the app. Please reopen it to proceed with your restoration.", preferredStyle: .alert)
            secondAlert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
            secondAlert.addAction(UIAlertAction(title: "Restore", style: .destructive, handler: {_ in
                
                if let actualCoreVC = self.coreVC {
                    actualCoreVC.resetApp()
                }
            }))
            self.present(secondAlert, animated: true)
        }))
        self.present(alert, animated: true)
    }
    
}
