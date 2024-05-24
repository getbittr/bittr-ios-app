//
//  PinViewController.swift
//  bittr
//
//  Created by Tom Melters on 29/08/2023.
//

import UIKit
//import KeychainSwift

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
    
    @IBOutlet weak var background1: UIView!
    @IBOutlet weak var background2: UIView!
    @IBOutlet weak var background3: UIView!
    @IBOutlet weak var background4: UIView!
    @IBOutlet weak var background5: UIView!
    @IBOutlet weak var background6: UIView!
    @IBOutlet weak var background7: UIView!
    @IBOutlet weak var background8: UIView!
    @IBOutlet weak var background9: UIView!
    @IBOutlet weak var background0: UIView!
    @IBOutlet weak var backgroundBackSpace: UIView!
    var allBackgrounds:[UIView]?
    
    var correctPin:String?
    
    var coreVC:CoreViewController?
    
    // Changing elements
    var embeddingView = "core"
    var upperViewController:UIViewController?
    @IBOutlet weak var topLabel: UILabel!
    @IBOutlet weak var nextButtonLabel: UILabel!
    @IBOutlet weak var restoreButtonLabel: UILabel!
    @IBOutlet weak var restoreButtonView: UIView!
    
    override func viewDidLoad() {
        super.viewDidLoad()

        if self.embeddingView == "core" {
            self.topLabel.text = "Enter your PIN code"
            self.nextButtonLabel.text = "Confirm"
            self.restoreButtonLabel.text = "Restore wallet"
            self.restoreButtonView.alpha = 1
        } else if self.embeddingView == "signup5" {
            self.topLabel.text = "Set a PIN code for secure access to your wallet"
            self.nextButtonLabel.text = "Next"
            self.restoreButtonLabel.text = ""
            self.restoreButtonView.alpha = 0
        } else if self.embeddingView == "signup6" {
            self.topLabel.text = "Confirm your PIN code"
            self.nextButtonLabel.text = "Confirm"
            self.restoreButtonLabel.text = "Back"
            self.restoreButtonView.alpha = 1
        } else if self.embeddingView == "restore2" {
            self.topLabel.text = "Set a PIN code for secure access to your wallet"
            self.nextButtonLabel.text = "Next"
            self.restoreButtonLabel.text = ""
            self.restoreButtonView.alpha = 0
        } else if self.embeddingView == "restore3" {
            self.topLabel.text = "Confirm your PIN code"
            self.nextButtonLabel.text = "Confirm"
            self.restoreButtonLabel.text = "Back"
            self.restoreButtonView.alpha = 1
        }
        
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
        }
        
        allBackgrounds = [background0, background1, background2, background3, background4, background5, background6, background7, background8, background9, backgroundBackSpace]
        for eachBackground in allBackgrounds! {
            eachBackground.layer.cornerRadius = 45
        }
    }
    
    @IBAction func numberButtonTapped(_ sender: UIButton) {
        
        pinTextField.insertText(String(sender.tag))
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.allBackgrounds![sender.tag].alpha = 0
        }
    }
    
    @IBAction func backspaceButtonTapped(_ sender: UIButton) {
        
        pinTextField.deleteBackward()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.allBackgrounds![sender.tag].alpha = 0
        }
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
        
        if self.embeddingView == "core" {
            // Check internet connection.
            if !Reachability.isConnectedToNetwork() {
                // User not connected to internet.
                let alert = UIAlertController(title: "Check your connection", message: "You don't seem to be connected to the internet. Please try to connect.", preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "Okay", style: .cancel, handler: nil))
                self.present(alert, animated: true)
                return
            }
            
            if CacheManager.getFailedPinAttempts() > 9 {
                // Wrong pin has been entered 10 times.
                let alert = UIAlertController(title: "Restore wallet", message: "You've entered an incorrect pin too many times. Please restore your wallet.", preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "Okay", style: .cancel, handler: { _ in
                    self.pinTextField.text = ""
                    if let actualCoreVC = self.coreVC {
                        actualCoreVC.resetApp(nodeIsRunning: false)
                    }
                }))
                self.present(alert, animated: true)
                return
            }
            
            if let actualCorrectPin = self.correctPin {
                
                if actualCorrectPin == self.pinTextField.text {
                    // Correct pin.
                    CacheManager.resetFailedPinAttempts()
                    if let actualCoreVC = self.coreVC {
                        
                        self.pinSpinner.startAnimating()
                        
                        // Step 1.
                        actualCoreVC.correctPin(spinner:self.pinSpinner)
                    }
                } else {
                    // Wrong pin.
                    CacheManager.increaseFailedPinAttempts()
                    let alert = UIAlertController(title: "Incorrect PIN", message: "Please enter your correct pin. If you've forgotten it, please restore your wallet.", preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: "Okay", style: .cancel, handler: { _ in
                        self.pinTextField.text = ""
                    }))
                    self.present(alert, animated: true)
                }
            } else {
                // No pin found in storage.
                print("No pin found in storage.")
            }
        } else if self.embeddingView == "signup5" {
            
            if let actualSignup5VC = self.upperViewController as? Signup5ViewController {
                
                actualSignup5VC.nextButtonTapped(enteredPin: self.pinTextField.text ?? "")
            }
        } else if self.embeddingView == "signup6" {
            
            if let actualSignup6VC = self.upperViewController as? Signup6ViewController {
                
                actualSignup6VC.nextButtonTapped(enteredPin: self.pinTextField.text ?? "")
            }
        } else if self.embeddingView == "restore2" {
            
            if let actualRestore2VC = self.upperViewController as? Restore2ViewController {
                
                actualRestore2VC.nextButtonTapped(enteredPin: self.pinTextField.text ?? "")
            }
        } else if self.embeddingView == "restore3" {
            
            if let actualRestore3VC = self.upperViewController as? Restore3ViewController {
                
                actualRestore3VC.nextButtonTapped(enteredPin: self.pinTextField.text ?? "")
            }
        }
    }
    
    @IBAction func restoreButtonTapped(_ sender: UIButton) {
        
        if self.embeddingView == "core" {
            
            let alert = UIAlertController(title: "Restore wallet", message: "\nThis app only supports one wallet simultaneously. Restoring a wallet means removing this current wallet from your device.\n\nOnly restore a wallet if you're sure you've properly backed up this current wallet.", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
            alert.addAction(UIAlertAction(title: "Restore", style: .destructive, handler: {_ in
                
                let secondAlert = UIAlertController(title: "Restore wallet", message: "\nAre you sure you want to remove this current wallet from your device and replace it with a restored one?\n\nIf you tap Restore, we'll reset and close the app. Please reopen it to proceed with your restoration.", preferredStyle: .alert)
                secondAlert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
                secondAlert.addAction(UIAlertAction(title: "Restore", style: .destructive, handler: {_ in
                    
                    if let actualCoreVC = self.coreVC {
                        actualCoreVC.resetApp(nodeIsRunning: false)
                    }
                }))
                self.present(secondAlert, animated: true)
            }))
            self.present(alert, animated: true)
            
        } else if self.embeddingView == "signup5" {
            return
        } else if self.embeddingView == "signup6" {
            
            if let actualSignup6VC = self.upperViewController as? Signup6ViewController {
                
                actualSignup6VC.backButtonTapped()
            }
        } else if self.embeddingView == "restore2" {
            return
        } else if self.embeddingView == "restore3" {
            
            if let actualRestore3VC = self.upperViewController as? Restore3ViewController {
                
                actualRestore3VC.backButtonTapped()
            }
        }
        
    }
    
    @IBAction func pinButtonTouchDown(_ sender: UIButton) {
        
        self.allBackgrounds![sender.tag].alpha = 0.1
    }
    
    @IBAction func pinButtonCancel(_ sender: UIButton) {
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.allBackgrounds![sender.tag].alpha = 0
        }
    }
    
}
