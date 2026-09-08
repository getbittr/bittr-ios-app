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
    @IBOutlet weak var imageBackspace: UIImageView!
    @IBOutlet weak var pinTextField: UITextField!
    @IBOutlet weak var pinSpinner: UIActivityIndicatorView!
    
    // Keypad elements
    @IBOutlet var keyButtons:[UIButton]!
    @IBOutlet var keyLabels:[UILabel]!
    @IBOutlet var keyBackgrounds:[UIView]!
    
    // Variables
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
        
        // Put the keypad in tag order.
        self.keyButtons.sort { $0.tag < $1.tag }
        self.keyLabels.sort { $0.tag < $1.tag }
        self.keyBackgrounds.sort { $0.tag < $1.tag }
        
        let keyTestIDs = [TestID.Pin.button0, TestID.Pin.button1, TestID.Pin.button2, TestID.Pin.button3, TestID.Pin.button4, TestID.Pin.button5, TestID.Pin.button6, TestID.Pin.button7, TestID.Pin.button8, TestID.Pin.button9, TestID.Pin.buttonBackspace]
        for (eachButton, eachTestID) in zip(self.keyButtons, keyTestIDs) {
            eachButton.accessibilityIdentifier = eachTestID
        }
        self.confirmPinButton.accessibilityIdentifier = TestID.Pin.confirmButton
        self.restoreWalletButton.accessibilityIdentifier = TestID.Pin.restoreButton
        self.pinTextField.accessibilityIdentifier = TestID.Pin.pinTextField

        // Set elements according to superview.
        self.topLabel.text = Language.getWord(withID: self.embeddingView.titleWord)
        self.topLabel.accessibilityIdentifier = self.embeddingView.titleTestID
        self.nextButtonLabel.text = Language.getWord(withID: self.embeddingView.confirmWord)
        if let restoreWord = self.embeddingView.restoreWord {
            self.restoreButtonLabel.text = Language.getWord(withID: restoreWord)
            self.restoreButtonView.alpha = 1
        } else {
            self.restoreButtonLabel.text = ""
            self.restoreButtonView.alpha = 0
        }
        
        // Corner radii
        self.confirmPinView.layer.cornerRadius = 8
        self.confirmPinView.setShadow()
        
        // Button titles
        let allButtons:[UIButton] = self.keyButtons + [self.confirmPinButton, self.restoreWalletButton]
        for eachButton in allButtons { eachButton.setTitle("", for: .normal) }
        
        // Text field
        self.pinTextField.delegate = self
        
        // Configure button backgrounds.
        for eachBackground in self.keyBackgrounds { eachBackground.layer.cornerRadius = 45 }
        
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
            self.keyBackgrounds[sender.tag].alpha = 0
        }
        
        // Check if PIN is already at max length (8 digits)
        if (pinTextField.text?.count ?? 0) >= 8 {
            self.showAlert(title: Language.getWord(withID: "pinlength"), message: Language.getWord(withID: "pincanbeupto8"), buttons: [.dismiss(Language.getWord(withID: "okay"))])
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
            self.keyBackgrounds[sender.tag].alpha = 0
        }
    }
    
    @IBAction func confirmPinButtonTapped(_ sender: UIButton) {
        
        // Check if PIN is empty or too short
        if (pinTextField.text?.count ?? 0) < 4 {
            self.showAlert(title: Language.getWord(withID: "pinrequired"), message: Language.getWord(withID: "pinshouldbe4to8"), buttons: [.dismiss(Language.getWord(withID: "okay"))])
            return
        }
        
        switch self.embeddingView {
        case .core:
            guard (self.coreVC ?? self).checkInternetConnection() else { return }
            guard CacheManager.hasPin() else {
                Log.info("No pin found in storage.")
                return
            }
            
            if CacheManager.getFailedPinAttempts() >= 10 {
                Log.info("Wallet is locked out after 10 failed PIN attempts.")
                self.clearPinField()
                self.removeWallet()
                return
            }
            
            if CacheManager.verifyPin(self.pinTextField.text ?? "") {
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
                    self.showAlert(title: Language.getWord(withID: "pinwarning"), message: Language.getWord(withID: "pinwarning2") + "\n\n" + attemptsMessage, buttons: [.dismiss(Language.getWord(withID: "okay")), .action(Language.getWord(withID: "forgotpin")) { self.coreVC!.startPinReset() }])
                    return
                }

                self.showAlert(title: Language.getWord(withID: "incorrectpin"), message: Language.getWord(withID: "incorrectpin2") + "\n\n" + attemptsMessage, buttons: [.action(Language.getWord(withID: "okay")) { self.clearPinField() }])
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
        self.showAlert(title: Language.getWord(withID: "restorewallet"), message: Language.getWord(withID: "pinlock"), buttons: [.dismiss(Language.getWord(withID: "okay"))])
        
        Log.info("Remove wallet from device.")
        self.coreVC?.removingWalletForIncorrectPin = true
        self.coreVC?.restoreWalletTapped()
    }
    
    func clearPinField() {
        self.pinTextField.text = ""
        self.pinCollectionView.reloadData()
    }
    
    @IBAction func restoreButtonTapped(_ sender: UIButton) {
        switch self.embeddingView {
        case .core:
            self.showAlert(title: Language.getWord(withID: "forgotpin"), message: Language.getWord(withID: "forgotpin2"), buttons: [.dismiss(Language.getWord(withID: "cancel")), .action(Language.getWord(withID: "reset")) { self.coreVC!.startPinReset() }])
        case .signup6:
            (self.upperViewController as? Signup6ViewController)?.backButtonTapped()
        case .restore3:
            (self.upperViewController as? Restore3ViewController)?.backButtonTapped()
        default: return
        }
    }
    
    @IBAction func pinButtonTouchDown(_ sender: UIButton) {
        // Show button feedback.
        self.keyBackgrounds[sender.tag].alpha = 0.1
    }
    
    @IBAction func pinButtonCancel(_ sender: UIButton) {
        // Hide button feedback.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.keyBackgrounds[sender.tag].alpha = 0
        }
    }
    
    @objc func changeColors() {
        
        self.view.backgroundColor = Colors.getColor("yelloworblue3")
        self.topLabel.textColor = Colors.getColor("blackorwhite")
        self.imageBackspace.tintColor = Colors.getColor("blackorwhite")
        self.confirmPinView.backgroundColor = Colors.getColor("blackorblue1")
        self.pinTextField.textColor = Colors.getColor("blackorblue1")
        for eachLabel in self.keyLabels { eachLabel.textColor = Colors.getColor("blackorwhite") }
        self.restoreButtonLabel.textColor = Colors.getColor(CacheManager.darkModeIsOn() ? "blackorwhite" : "transparentblack")
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
        guard let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "PinCell", for: indexPath) as? PinCollectionViewCell else { return UICollectionViewCell() }
        return cell
    }
    
}

enum EmbeddingView {
    case core
    case signup5
    case signup6
    case restore2
    case restore3
    
    var titleWord:String {
        switch self {
        case .core: return "enteryourpincode"
        case .signup5, .restore2: return "setapin"
        case .signup6, .restore3: return "confirmyourpin"
        }
    }
    
    var titleTestID:String {
        switch self {
        case .core: return TestID.Unlock.topLabel
        case .signup5: return TestID.Signup.Create.PinSet.topLabel
        case .signup6: return TestID.Signup.Create.PinConfirm.topLabel
        case .restore2: return TestID.Signup.Restore.PinSet.topLabel
        case .restore3: return TestID.Signup.Restore.PinConfirm.topLabel
        }
    }
    
    var confirmWord:String {
        switch self {
        case .core, .signup6, .restore3: return "confirm"
        case .signup5, .restore2: return "next"
        }
    }
    
    var restoreWord:String? {
        switch self {
        case .core: return "forgotpin"
        case .signup6, .restore3: return "back"
        case .signup5, .restore2: return nil
        }
    }
}
