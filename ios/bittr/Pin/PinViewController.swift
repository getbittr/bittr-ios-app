//
//  PinViewController.swift
//  bittr
//
//  Created by Tom Melters on 29/08/2023.
//

import UIKit

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
    var embeddingView:EmbeddingView = .core
    var upperViewController:UIViewController?
    @IBOutlet weak var topLabel: UILabel!
    @IBOutlet weak var nextButtonLabel: UILabel!
    @IBOutlet weak var restoreButtonLabel: UILabel!
    @IBOutlet weak var restoreButtonView: UIView!
    
    override func viewDidLoad() {
        super.viewDidLoad()

        self.button0.accessibilityIdentifier = TestID.Pin.button0
        self.button1.accessibilityIdentifier = TestID.Pin.button1
        self.button2.accessibilityIdentifier = TestID.Pin.button2
        self.button3.accessibilityIdentifier = TestID.Pin.button3
        self.button4.accessibilityIdentifier = TestID.Pin.button4
        self.button5.accessibilityIdentifier = TestID.Pin.button5
        self.button6.accessibilityIdentifier = TestID.Pin.button6
        self.button7.accessibilityIdentifier = TestID.Pin.button7
        self.button8.accessibilityIdentifier = TestID.Pin.button8
        self.button9.accessibilityIdentifier = TestID.Pin.button9
        self.buttonBackspace.accessibilityIdentifier = TestID.Pin.buttonBackspace
        self.confirmPinButton.accessibilityIdentifier = TestID.Pin.confirmButton
        self.restoreWalletButton.accessibilityIdentifier = TestID.Pin.restoreButton
        self.pinTextField.accessibilityIdentifier = TestID.Pin.pinTextField

        // Set elements according to superview.
        switch self.embeddingView {
        case .core:
            self.topLabel.text = Language.getWord(withID: "enteryourpincode")
            self.topLabel.accessibilityIdentifier = TestID.Unlock.topLabel
            self.nextButtonLabel.text = Language.getWord(withID: "confirm")
            self.restoreButtonLabel.text = Language.getWord(withID: "forgotpin")
            self.restoreButtonView.alpha = 1
        case .signup5:
            self.topLabel.text = Language.getWord(withID: "setapin")
            self.topLabel.accessibilityIdentifier = TestID.Signup.Create.PinSet.topLabel
            self.nextButtonLabel.text = Language.getWord(withID: "next")
            self.restoreButtonLabel.text = ""
            self.restoreButtonView.alpha = 0
        case .signup6:
            self.topLabel.text = Language.getWord(withID: "confirmyourpin")
            self.topLabel.accessibilityIdentifier = TestID.Signup.Create.PinConfirm.topLabel
            self.nextButtonLabel.text = Language.getWord(withID: "confirm")
            self.restoreButtonLabel.text = Language.getWord(withID: "back")
            self.restoreButtonView.alpha = 1
        case .restore2:
            self.topLabel.text = Language.getWord(withID: "setapin")
            self.topLabel.accessibilityIdentifier = TestID.Signup.Restore.PinSet.topLabel
            self.nextButtonLabel.text = Language.getWord(withID: "next")
            self.restoreButtonLabel.text = ""
            self.restoreButtonView.alpha = 0
        case .restore3:
            self.topLabel.text = Language.getWord(withID: "confirmyourpin")
            self.topLabel.accessibilityIdentifier = TestID.Signup.Restore.PinConfirm.topLabel
            self.nextButtonLabel.text = Language.getWord(withID: "confirm")
            self.restoreButtonLabel.text = Language.getWord(withID: "back")
            self.restoreButtonView.alpha = 1
        }
        
        // Corner radii
        self.confirmPinView.layer.cornerRadius = 8
        self.confirmPinView.setShadow()
        
        // Button titles
        let allButtons = [self.confirmPinButton, self.restoreWalletButton, self.button1, self.button2, self.button3, self.button4, self.button5, self.button6, self.button7, self.button8, self.button9, self.button0, self.buttonBackspace]
        for eachButton in allButtons {
            eachButton?.setTitle("", for: .normal)
        }
        
        // Text field
        self.pinTextField.delegate = self
        
        // Get correct pin
        self.correctPin = CacheManager.getPin()
        
        // Configure button backgrounds.
        self.allBackgrounds = [background0, background1, background2, background3, background4, background5, background6, background7, background8, background9, backgroundBackSpace]
        for eachBackground in self.allBackgrounds! {
            eachBackground.layer.cornerRadius = 45
        }
        
        // Observers
        NotificationCenter.default.addObserver(self, selector: #selector(changeColors), name: NSNotification.Name(rawValue: "changecolors"), object: nil)
        
        // Collection view
        self.pinCollectionView.delegate = self
        self.pinCollectionView.dataSource = self
    }
    
    override func viewWillAppear(_ animated: Bool) {
        self.changeColors()
    }
    
    @IBAction func numberButtonTapped(_ sender: UIButton) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.allBackgrounds![sender.tag].alpha = 0
        }
        
        // Check if PIN is already at max length (8 digits)
        if (pinTextField.text?.count ?? 0) >= 8 {
            self.showAlert(presentingController: self.coreVC ?? self, title: Language.getWord(withID: "pinlength"), message: Language.getWord(withID: "pincanbeupto8"), buttons: [Language.getWord(withID: "okay")], actions: nil)
            return
        }
        
        // Update text field.
        self.pinTextField.insertText(String(sender.tag))
        self.pinCollectionView.reloadData()
    }
    
    @IBAction func backspaceButtonTapped(_ sender: UIButton) {
        
        // Update text field.
        self.pinTextField.deleteBackward()
        self.pinCollectionView.reloadData()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.allBackgrounds![sender.tag].alpha = 0
        }
    }
    
    @IBAction func confirmPinButtonTapped(_ sender: UIButton) {
        
        // Check if PIN is empty or too short
        if (pinTextField.text?.count ?? 0) < 4 {
            self.showAlert(presentingController: self.coreVC ?? self, title: Language.getWord(withID: "pinrequired"), message: Language.getWord(withID: "pinshouldbe4to8"), buttons: [Language.getWord(withID: "okay")], actions: nil)
            return
        }
        
        switch self.embeddingView {
        case .core:
            guard (self.coreVC ?? self).checkInternetConnection() else { return }
            guard self.correctPin != nil else {
                Log.info("No pin found in storage.")
                return
            }
            
            if CacheManager.getFailedPinAttempts() >= 10 {
                Log.info("Wallet is locked out after 10 failed PIN attempts.")
                self.clearPinField()
                self.removeWallet()
                return
            }
            
            if self.correctPin! == self.pinTextField.text {
                // Correct pin.
                CacheManager.resetFailedPinAttempts()
                self.pinSpinner.startAnimating()
                
                // Hide pin and sync wallet.
                self.coreVC?.userHasSignedIn = true
                self.coreVC?.lowerPinView(spinner: self.pinSpinner)
                self.coreVC?.startWallet()
            } else {
                // Wrong pin.
                CacheManager.increaseFailedPinAttempts()
                self.clearPinField()
                
                if CacheManager.getFailedPinAttempts() >= 10 {
                    Log.info("Wrong pin has been entered 10 times.")
                    self.removeWallet()
                    return
                }

                // Tell the user how many tries remain before the 10-attempt
                // wipe (singular wording for the final attempt).
                let attemptsLeft = 10 - CacheManager.getFailedPinAttempts()
                let attemptsMessage = attemptsLeft == 1
                    ? Language.getWord(withID: "pinattemptleft")
                    : Language.getWord(withID: "pinattemptsleft").replacingOccurrences(of: "<attempts>", with: "\(attemptsLeft)")

                // Warn well before the 10-attempt wipe and steer anyone who
                // still has their recovery phrase to the non-destructive
                // Forgot PIN flow — the wipe can cost them their Lightning
                // funds, so we want them recovering by mnemonic instead.
                if CacheManager.getFailedPinAttempts() == 3 {
                    self.showAlert(presentingController: self.coreVC ?? self, title: Language.getWord(withID: "pinwarning"), message: Language.getWord(withID: "pinwarning2") + "\n\n" + attemptsMessage, buttons: [Language.getWord(withID: "okay"), Language.getWord(withID: "forgotpin")], actions: [nil, #selector(self.startPinReset)])
                    return
                }

                self.showAlert(presentingController: self.coreVC ?? self, title: Language.getWord(withID: "incorrectpin"), message: Language.getWord(withID: "incorrectpin2") + "\n\n" + attemptsMessage, buttons: [Language.getWord(withID: "okay")], actions: [#selector(self.clearPinField)])
            }
        case .signup5:
            (self.upperViewController as? Signup5ViewController)?.nextButtonTapped(enteredPin: self.pinTextField.text ?? "")
        case .signup6:
            (self.upperViewController as? Signup6ViewController)?.nextButtonTapped(enteredPin: self.pinTextField.text ?? "")
        case .restore2:
            (self.upperViewController as? Restore2ViewController)?.nextButtonTapped(enteredPin: self.pinTextField.text ?? "")
        case .restore3:
            (self.upperViewController as? Restore3ViewController)?.nextButtonTapped(enteredPin: self.pinTextField.text ?? "")
        }
    }
    
    func removeWallet() {
        self.showAlert(presentingController: self.coreVC ?? self, title: Language.getWord(withID: "restorewallet"), message: Language.getWord(withID: "pinlock"), buttons: [Language.getWord(withID: "okay")], actions: nil)
        
        Log.info("Remove wallet from device.")
        self.coreVC?.removingWalletForIncorrectPin = true
        self.coreVC?.restoreWalletTapped()
    }
    
    @objc func clearPinField() {
        self.hideAlert()
        self.pinTextField.text = ""
        self.pinCollectionView.reloadData()
    }
    
    @IBAction func restoreButtonTapped(_ sender: UIButton) {
        
        switch self.embeddingView {
        case .core:
            self.showAlert(presentingController: self.coreVC!, title: Language.getWord(withID: "forgotpin"), message: Language.getWord(withID: "forgotpin2"), buttons: [Language.getWord(withID: "cancel"), Language.getWord(withID: "reset")], actions: [nil, #selector(self.startPinReset)])
        case .signup6:
            (self.upperViewController as? Signup6ViewController)?.backButtonTapped()
        case .restore3:
            (self.upperViewController as? Restore3ViewController)?.backButtonTapped()
        default: return
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
        self.imageBackspace.tintColor = Colors.getColor("blackorwhite")
        self.confirmPinView.backgroundColor = Colors.getColor("blackorblue1")
        self.pinTextField.textColor = Colors.getColor("blackorblue1")
        for eachLabel in [self.label1, self.label2, self.label3, self.label4, self.label5, self.label6, self.label7, self.label8, self.label9, self.label0] {
            eachLabel!.textColor = Colors.getColor("blackorwhite")
        }
        if CacheManager.darkModeIsOn() {
            self.restoreButtonLabel.textColor = Colors.getColor("blackorwhite")
        } else {
            self.restoreButtonLabel.textColor = Colors.getColor("transparentblack")
        }
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

enum EmbeddingView {
    case core
    case signup5
    case signup6
    case restore2
    case restore3
}
