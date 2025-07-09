//
//  PinViewController.swift
//  bittr
//
//  Created by Tom Melters on 29/08/2023.
//

import UIKit
//import KeychainSwift

class PinViewController: UIViewController, UITextFieldDelegate, UICollectionViewDelegate, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {

    // Views
    @IBOutlet weak var confirmPinView: UIView!
    @IBOutlet weak var confirmPinButton: UIButton!
    @IBOutlet weak var restoreWalletButton: UIButton!
    @IBOutlet weak var pinCollectionView: UICollectionView!
    @IBOutlet weak var pinCollectionViewWidth: NSLayoutConstraint!
    
    // Number labels
    @IBOutlet weak var label1: UILabel!
    @IBOutlet weak var label2: UILabel!
    @IBOutlet weak var label3: UILabel!
    @IBOutlet weak var label4: UILabel!
    @IBOutlet weak var label5: UILabel!
    @IBOutlet weak var label6: UILabel!
    @IBOutlet weak var label7: UILabel!
    @IBOutlet weak var label8: UILabel!
    @IBOutlet weak var label9: UILabel!
    @IBOutlet weak var label0: UILabel!
    @IBOutlet weak var imageBackspace: UIImageView!
    var allLabels = [UILabel]()
    
    // Buttons
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
    
    // Button backgrounds
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
    
    // Variables
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

        // Set elements according to superview.
        if self.embeddingView == "core" {
            self.topLabel.text = Language.getWord(withID: "enteryourpincode")
            self.nextButtonLabel.text = Language.getWord(withID: "confirm")
            self.restoreButtonLabel.text = Language.getWord(withID: "forgotpin")
            self.restoreButtonView.alpha = 1
        } else if self.embeddingView == "signup5" {
            self.topLabel.text = Language.getWord(withID: "setapin")
            self.nextButtonLabel.text = Language.getWord(withID: "next")
            self.restoreButtonLabel.text = ""
            self.restoreButtonView.alpha = 0
        } else if self.embeddingView == "signup6" {
            self.topLabel.text = Language.getWord(withID: "confirmyourpin")
            self.nextButtonLabel.text = Language.getWord(withID: "confirm")
            self.restoreButtonLabel.text = Language.getWord(withID: "back")
            self.restoreButtonView.alpha = 1
        } else if self.embeddingView == "restore2" {
            self.topLabel.text = Language.getWord(withID: "setapin")
            self.nextButtonLabel.text = Language.getWord(withID: "next")
            self.restoreButtonLabel.text = ""
            self.restoreButtonView.alpha = 0
        } else if self.embeddingView == "restore3" {
            self.topLabel.text = Language.getWord(withID: "confirmyourpin")
            self.nextButtonLabel.text = Language.getWord(withID: "confirm")
            self.restoreButtonLabel.text = Language.getWord(withID: "back")
            self.restoreButtonView.alpha = 1
        }
        
        // Corner radii and button titles.
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
        
        if let actualPin = CacheManager.getPin() {
            self.correctPin = actualPin
        }
        
        // Configure button backgrounds.
        allBackgrounds = [background0, background1, background2, background3, background4, background5, background6, background7, background8, background9, backgroundBackSpace]
        for eachBackground in allBackgrounds! {
            eachBackground.layer.cornerRadius = 45
        }
        
        self.allLabels = [self.label1, self.label2, self.label3, self.label4, self.label5, self.label6, self.label7, self.label8, self.label9, self.label0]
        
        NotificationCenter.default.addObserver(self, selector: #selector(changeColors), name: NSNotification.Name(rawValue: "changecolors"), object: nil)
        
        // Collection view.
        self.pinCollectionView.delegate = self
        self.pinCollectionView.dataSource = self
        
        self.changeColors()
    }
    
    @IBAction func numberButtonTapped(_ sender: UIButton) {
        
        // Check if PIN is already at max length (8 digits)
        if (pinTextField.text?.count ?? 0) >= 8 {
            self.showAlert(presentingController: self, title: Language.getWord(withID: "pinlength"), message: Language.getWord(withID: "pincanbeupto8"), buttons: [Language.getWord(withID: "okay")], actions: nil)
            return
        }
        
        // Update text field.
        pinTextField.insertText(String(sender.tag))
        self.pinCollectionView.reloadData()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.allBackgrounds![sender.tag].alpha = 0
        }
    }
    
    @IBAction func backspaceButtonTapped(_ sender: UIButton) {
        
        // Update text field.
        pinTextField.deleteBackward()
        self.pinCollectionView.reloadData()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.allBackgrounds![sender.tag].alpha = 0
        }
    }
    
    @IBAction func confirmPinButtonTapped(_ sender: UIButton) {
        
        // Check if PIN is empty or too short
        if (pinTextField.text?.count ?? 0) < 4 {
            self.showAlert(presentingController: self, title: Language.getWord(withID: "pinrequired"), message: Language.getWord(withID: "pinshouldbe4to8"), buttons: [Language.getWord(withID: "okay")], actions: nil)
            return
        }
        
        if self.embeddingView == "core" {
            
            // Check internet connection.
            if !Reachability.isConnectedToNetwork() {
                // User not connected to internet.
                self.showAlert(presentingController: self, title: Language.getWord(withID: "checkyourconnection"), message: Language.getWord(withID: "trytoconnect"), buttons: [Language.getWord(withID: "okay")], actions: nil)
                return
            }
            
            if CacheManager.getFailedPinAttempts() > 9 {
                // Wrong pin has been entered 10 times.
                self.showAlert(presentingController: self, title: Language.getWord(withID: "restorewallet"), message: Language.getWord(withID: "pinlock"), buttons: [Language.getWord(withID: "okay")], actions: [#selector(self.clearPinField)])
                if let actualCoreVC = self.coreVC {
                    actualCoreVC.resetApp(nodeIsRunning: false)
                }
                return
            }
            
            if let actualCorrectPin = self.correctPin {
                if actualCorrectPin == self.pinTextField.text {
                    // Correct pin.
                    CacheManager.resetFailedPinAttempts()
                    if let actualCoreVC = self.coreVC {
                        self.pinSpinner.startAnimating()
                        actualCoreVC.correctPin(spinner:self.pinSpinner)
                    }
                } else {
                    // Wrong pin.
                    CacheManager.increaseFailedPinAttempts()
                    self.showAlert(presentingController: self, title: Language.getWord(withID: "incorrectpin"), message: Language.getWord(withID: "incorrectpin2"), buttons: [Language.getWord(withID: "okay")], actions: [#selector(self.clearPinField)])
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
    
    @objc func clearPinField() {
        self.hideAlert()
        self.pinTextField.text = ""
    }
    
    @IBAction func restoreButtonTapped(_ sender: UIButton) {
        
        if self.embeddingView == "core" {
            self.showAlert(presentingController: self.coreVC!, title: Language.getWord(withID: "forgotpin"), message: Language.getWord(withID: "forgotpin2"), buttons: [Language.getWord(withID: "cancel"), Language.getWord(withID: "reset")], actions: [nil, #selector(self.startPinReset)])
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
    
    @objc func startPinReset() {
        self.hideAlert()
        self.coreVC!.startPinReset()
    }
    
    @IBAction func pinButtonTouchDown(_ sender: UIButton) {
        
        // Show button feedback.
        self.allBackgrounds![sender.tag].alpha = 0.1
    }
    
    @IBAction func pinButtonCancel(_ sender: UIButton) {
        
        // Hide button feedback.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.allBackgrounds![sender.tag].alpha = 0
        }
    }
    
    @objc func changeColors() {
        
        self.view.backgroundColor = Colors.getColor("yelloworblue3")
        self.topLabel.textColor = Colors.getColor("blackorwhite")
        if CacheManager.darkModeIsOn() {
            self.restoreButtonLabel.textColor = Colors.getColor("blackorwhite")
        } else {
            self.restoreButtonLabel.textColor = Colors.getColor("transparentblack")
        }
        for eachLabel in self.allLabels {
            eachLabel.textColor = Colors.getColor("blackorwhite")
        }
        self.imageBackspace.tintColor = Colors.getColor("blackorwhite")
        self.confirmPinView.backgroundColor = Colors.getColor("blackorblue1")
        self.pinTextField.textColor = Colors.getColor("blackorblue1")
    }
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        
        self.pinCollectionView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        
        let pinLength:Int = self.pinTextField.text?.count ?? 0
        if pinLength == 0 {
            self.pinCollectionViewWidth.constant = 0
        } else {
            var collectionViewWidth:CGFloat = CGFloat((pinLength * 40) + ((pinLength-1) * 10))
            if collectionViewWidth > self.view.bounds.width {
                collectionViewWidth = self.view.bounds.width
                self.pinCollectionView.contentInset = UIEdgeInsets(top: 0, left: 45, bottom: 0, right: 45)
            }
            self.pinCollectionViewWidth.constant = collectionViewWidth
        }
        
        return pinLength
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        return CGSize(width: 40, height: 60)
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        
        if let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "PinCell", for: indexPath) as? PinCollectionViewCell {
            
            return cell
        } else {
            return UICollectionViewCell()
        }
    }
    
}
