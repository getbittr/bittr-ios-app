//
//  Transfer15ViewController.swift
//  bittr
//
//  Created by Tom Melters on 15/06/2023.
//

import UIKit
import BitcoinDevKit
import UserNotifications
import Sentry

class Transfer15ViewController: UIViewController, UITextFieldDelegate, UNUserNotificationCenterDelegate {
    
    // User has received code in email. Send this code to the bittr API.
    
    @IBOutlet weak var topLabel: UILabel!
    @IBOutlet weak var codeView: UIView!
    @IBOutlet weak var nextView: UIView!
    @IBOutlet weak var codeTextField: UITextField!
    @IBOutlet weak var codeButton: UIButton!
    @IBOutlet weak var nextButton: UIButton!
    @IBOutlet weak var resendButton: UIButton!
    @IBOutlet weak var resendLabel: UILabel!
    
    // Scroll view and background buttons
    @IBOutlet weak var scrollView: UIScrollView!
    @IBOutlet weak var contentView: UIView!
    @IBOutlet weak var contentViewBottom: NSLayoutConstraint!
    @IBOutlet weak var backgroundButton2: UIButton!
    @IBOutlet weak var backgroundButton: UIButton!
    
    @IBOutlet weak var nextButtonLabel: UILabel!
    @IBOutlet weak var nextButtonActivityIndicator: UIActivityIndicatorView!
    
    var counter = 0
    
    var setSender = ""
    var start2Fa = false
    var hasAutoTriggered = false
    var coreVC:CoreViewController?
    var signupVC:SignupViewController?
    var ibanVC:RegisterIbanViewController?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Corner radii
        self.codeView.layer.cornerRadius = 13
        self.nextView.layer.cornerRadius = 13
        
        // Button titles
        self.codeButton.setTitle("", for: .normal)
        self.nextButton.setTitle("", for: .normal)
        self.resendButton.setTitle("", for: .normal)
        self.backgroundButton.setTitle("", for: .normal)
        self.backgroundButton2.setTitle("", for: .normal)
        
        // Email code text field.
        self.codeTextField.delegate = self
        self.codeTextField.addDoneButton(target: self, returnaction: #selector(self.doneButtonTapped))
        // Enable iOS keyboard suggestions for verification codes from email/SMS
        self.codeTextField.textContentType = .oneTimeCode
        
        // Notification observers.
        NotificationCenter.default.addObserver(self, selector: #selector(resume2Fa), name: NSNotification.Name(rawValue: "resume2fa"), object: nil)
        
        self.changeColors()
        self.setWords()
        
        // Reset auto-trigger flag
        self.hasAutoTriggered = false
    }
    
    func triggerOtpAutoFocus() {
        // Auto-focus on OTP field when triggered from previous page
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.codeTextField.becomeFirstResponder()
        }
    }
    
    @objc func doneButtonTapped() {
        self.view.endEditing(true)
    }
    
    @IBAction func codeButtonTapped(_ sender: UIButton) {
        
        self.codeTextField.becomeFirstResponder()
        self.codeButton.alpha = 0
    }
    
    @IBAction func nextButtonTapped(_ sender: UIButton) {
        
        self.view.endEditing(true)
        
        // Check whether code has been entered.
        self.updateButtonColor()
        if self.nextView.backgroundColor == UIColor.black {
            
            self.nextButtonLabel.alpha = 0
            self.nextButtonActivityIndicator.startAnimating()
            
            // Check push notifications status.
            let current = UNUserNotificationCenter.current()
            current.getNotificationSettings { (settings) in
                
                // Use a default value if accessibilityIdentifier is nil (for auto-triggered calls)
                self.setSender = sender.accessibilityIdentifier ?? "auto"
                
                if settings.authorizationStatus == .notDetermined {
                    // Notifications preference hasn't been set yet.
                    DispatchQueue.main.async {
                        self.showAlert(presentingController: self, title: Language.getWord(withID: "receivenotifications"), message: Language.getWord(withID: "receivenotifications2"), buttons: [Language.getWord(withID: "okay")], actions: [#selector(self.askForPushNotifications)])
                    }
                } else if settings.authorizationStatus == .authorized, CacheManager.getRegistrationToken() == nil {
                    // Notifications preference has been set but token hasn't been cached.
                    self.askForPushNotifications()
                } else {
                    self.check2Fa()
                }
            }
        }
    }
    
    
    @objc func resume2Fa() {
        if start2Fa == true {
            self.check2Fa()
            self.start2Fa = false
        }
    }
    
    func check2Fa() {
        
        let currentIbanID = self.signupVC?.currentIbanID ?? self.ibanVC!.currentIbanID
        
        for (index, eachIbanEntity) in self.coreVC!.bittrWallet.ibanEntities.enumerated() {
            if eachIbanEntity.id == currentIbanID {
                
                // Send email and verification code to bittr API.
                let parameters: [String: Any] = [
                    "email_address": eachIbanEntity.yourEmail,
                    "token_2fa": self.codeTextField.text!.trimmingCharacters(in: .whitespacesAndNewlines)
                ]
                
                let envUrl = "\(EnvironmentConfig.bittrAPIBaseURL)/verify/email/check2fa"
                
                Task {
                    await CallsManager.makeApiCall(url: envUrl, parameters: parameters, getOrPost: "POST") { result in
                        
                        switch result {
                        case .success(let receivedDictionary):
                            let emailToken = receivedDictionary["token"]
                            let errorMessage = receivedDictionary["message"]
                            if let actualEmailToken = emailToken as? String {
                                // Email address verified. Store email token in cache.
                                CacheManager.addEmailToken(ibanID: eachIbanEntity.id, emailToken: actualEmailToken)
                                
                                // Update the in-memory IBAN entity with the new email token
                                self.coreVC!.bittrWallet.ibanEntities[index].emailToken = actualEmailToken
                                
                                DispatchQueue.main.async {
                                    // Get wallet address.
                                    self.getAddress(page: self.setSender)
                                }
                            } else if let actualErrorMessage = errorMessage as? String {
                                if actualErrorMessage == "Invalid 2FA verification token provided" {
                                    DispatchQueue.main.async {
                                        self.nextButtonActivityIndicator.stopAnimating()
                                        self.nextButtonLabel.alpha = 1
                                        self.showAlert(presentingController: self, title: Language.getWord(withID: "oops"), message: Language.getWord(withID: "verificationfail"), buttons: [Language.getWord(withID: "okay")], actions: nil)
                                    }
                                }
                            }
                        case .failure(let error):
                            SentrySDK.capture(error: error)
                            DispatchQueue.main.async {
                                self.nextButtonActivityIndicator.stopAnimating()
                                self.nextButtonLabel.alpha = 1
                                self.showAlert(presentingController: self, title: Language.getWord(withID: "oops"), message: Language.getWord(withID: "verificationfail"), buttons: [Language.getWord(withID: "okay")], actions: nil)
                            }
                        }
                        
                    }
                }
            }
        }

    }
    
    
    func getAddress(page:String) {
        
        let currentIbanID = self.signupVC?.currentIbanID ?? self.ibanVC!.currentIbanID
        for eachIbanEntity in self.coreVC!.bittrWallet.ibanEntities {
            if eachIbanEntity.id == currentIbanID {
                
                let message = "I confirm I'm the sole owner of the bitcoin address I provided and I will be sending my own funds to bittr. Order: \(eachIbanEntity.emailToken.prefix(32)). IBAN: \(eachIbanEntity.yourIbanNumber)"
                self.createClient(message: message, page: page, iban: eachIbanEntity)
            }
        }
    }
    
    
    func createClient(message:String, page:String, iban:IbanEntity) {
        
        Task {
            // Get real onchain address.
            let wallet = LightningNodeService.shared.getWallet()
            let firstAddress = wallet?.peekAddress(keychain: .external, index: 0).address.description
            
            // Send to Bittr.
            self.createBittrAccount(receivedAddress: firstAddress ?? "", message: message, page: page, iban: iban)
        }
    }
    
    
    func createBittrAccount(receivedAddress:String, message:String, page:String, iban:IbanEntity) {
        
        let lightningPubKey = LightningNodeService.shared.nodeId()
        let xpub = LightningNodeService.shared.getXpub()
        
        let signature = try! LightningNodeService.shared.signMessageForPath(path: "m/84'/0'/0'/0/0", message: message)
        
        Task {
            do {
                let lightningSignature = try await LightningNodeService.shared.signMessage(message: message)
                
                let parameters: [String: Any] = [
                    "email": iban.yourEmail,
                    "email_token": iban.emailToken,
                    "bitcoin_address": receivedAddress,
                    "initial_address_type": "extended",
                    "category": "ios",
                    "bitcoin_message": message,
                    "bitcoin_signature": signature,
                    "iban": iban.yourIbanNumber,
                    "lightning_pubkey": lightningPubKey,
                    "lightning_signature": lightningSignature,
                    "xpub_key": xpub,
                    "xpub_addr_type": "bech32",
                    "xpub_path": "m/0/x",
                    "skip_xpub_usage_check": "true",
                    "ios_device_token": CacheManager.getRegistrationToken() ?? ""
                ]

                let envUrl = "\(EnvironmentConfig.bittrAPIBaseURL)/customer"
                
                await CallsManager.makeApiCall(url: envUrl, parameters: parameters, getOrPost: "POST") { result in
                    
                    switch result {
                    case .failure(let error):
                        DispatchQueue.main.async {
                            self.showAlert(presentingController: self, title: Language.getWord(withID: "oops"), message: Language.getWord(withID: "bittrsignupfail"), buttons: [Language.getWord(withID: "okay")], actions: nil)
                            SentrySDK.capture(error: error)
                        }
                    case .success(let receivedDictionary):
                        if let actualDataItems = receivedDictionary["data"] as? NSDictionary {
                            let dataOurIban = actualDataItems["iban"]
                            let dataCode = actualDataItems["deposit_code"]
                            let dataSwift = actualDataItems["swift"]
                            if let actualDataOurIban = dataOurIban as? String, let actualDataCode = dataCode as? String, let actualDataSwift = dataSwift as? String {
                                DispatchQueue.main.async {
                                    // Signup successful.
                                    
                                    // Add bittr details to cache.
                                    CacheManager.addBittrIban(ibanID: iban.id, ourIban: actualDataOurIban, ourSwift: actualDataSwift, yourCode: actualDataCode)
                                    for (index, eachIbanEntity) in self.coreVC!.bittrWallet.ibanEntities.enumerated() {
                                        if eachIbanEntity.id == iban.id {
                                            self.coreVC!.bittrWallet.ibanEntities[index].ourIbanNumber = actualDataOurIban
                                            self.coreVC!.bittrWallet.ibanEntities[index].ourSwift = actualDataSwift
                                            self.coreVC!.bittrWallet.ibanEntities[index].yourUniqueCode = actualDataCode
                                        }
                                    }
                                    
                                    // Stop spinner.
                                    self.nextButtonActivityIndicator.stopAnimating()
                                    self.nextButtonLabel.alpha = 1
                                    
                                    // Move to next page.
                                    self.signupVC?.moveToPage(12)
                                    self.ibanVC?.moveToPage(3)
                                }
                            }
                        } else if let actualApiMessage = receivedDictionary["message"] as? String {
                            // Some message has been received.
                            DispatchQueue.main.async {
                                if actualApiMessage == "Unable to create customer account (invalid iban)" {
                                    self.nextButtonActivityIndicator.stopAnimating()
                                    self.nextButtonLabel.alpha = 1
                                    self.codeTextField.text = nil
                                    
                                    self.showAlert(presentingController: self, title: Language.getWord(withID: "oops"), message: Language.getWord(withID: "bittrsignupfail2"), buttons: [Language.getWord(withID: "okay")], actions: [#selector(self.backToPreviousPage)])
                                } else {
                                    self.nextButtonActivityIndicator.stopAnimating()
                                    self.nextButtonLabel.alpha = 1
                                    self.codeTextField.text = nil
                                    
                                    self.showAlert(presentingController: self, title: Language.getWord(withID: "oops"), message: "\(Language.getWord(withID: "bittrsignupfail3")) (\(actualApiMessage).)", buttons: [Language.getWord(withID: "okay")], actions: [#selector(self.backToPreviousPage)])
                                }
                            }
                        }
                    }
                    
                }
            } catch let error as NSError {
                print(error)
                DispatchQueue.main.async {
                    SentrySDK.capture(error: error)
                }
            }
        }
    }
    
    @objc func backToPreviousPage() {
        self.hideAlert()
        self.signupVC?.moveToPage(10)
        self.ibanVC?.moveToPage(1)
    }
    
    
    @IBAction func resendCodeButtonTapped(_ sender: UIButton) {
        
        // User can request a new email verification code every 30 seconds.
        
        if self.counter == 0 {
            
            let currentIbanID = self.signupVC?.currentIbanID ?? self.ibanVC!.currentIbanID
            for eachIbanEntity in self.coreVC!.bittrWallet.ibanEntities {
                if eachIbanEntity.id == currentIbanID {
                    
                    let parameters: [String: Any] = [
                        "email": eachIbanEntity.yourEmail,
                        "category": "ios"
                    ]
                    
                    let envUrl = "\(EnvironmentConfig.bittrAPIBaseURL)/verify/email"
                    
                    Task {
                        await CallsManager.makeApiCall(url: envUrl, parameters: parameters, getOrPost: "POST") { result in
                            
                            switch result {
                            case .failure(let error):
                                DispatchQueue.main.async {
                                    self.showAlert(presentingController: self.coreVC ?? self, title: Language.getWord(withID: "oops"), message: Language.getWord(withID: "bittrsignupfail4"), buttons: [Language.getWord(withID: "okay")], actions: nil)
                                    SentrySDK.capture(error: error)
                                }
                            case .success(_):
                                DispatchQueue.main.async {
                                    self.showAlert(presentingController: self.coreVC ?? self, title: Language.getWord(withID: "emailresent"), message: "\(Language.getWord(withID: "emailresent2")) \(eachIbanEntity.yourEmail).", buttons: [Language.getWord(withID: "okay"), Language.getWord(withID: "changeemail")], actions: [nil, #selector(self.backToChangeEmail)])
                                    
                                    // Restart counter.
                                    self.counter = 30
                                    Timer.scheduledTimer(timeInterval: 1.0, target: self, selector: #selector(self.updateCounter), userInfo: nil, repeats: true)
                                }
                            }
                            
                        }
                    }
                }
            }
        } else {
            // Timer is still counting down.
            self.showAlert(presentingController: self.coreVC ?? self, title: "", message: Language.getWord(withID: "resendcode2"), buttons: [Language.getWord(withID: "okay"), Language.getWord(withID: "changeemail")], actions: [nil, #selector(self.backToChangeEmail)])
        }
    }
    
    @objc func backToChangeEmail() {
        self.hideAlert()
        self.signupVC?.moveToPage(10)
        self.ibanVC?.moveToPage(1)
    }
    
    
    @objc func updateCounter() {
        if counter > 0 {
            print("\(counter) seconds left")
            counter -= 1
        }
    }
    
    
    func updateButtonColor() {
        
        if self.codeTextField.text?.trimmingCharacters(in: .whitespacesAndNewlines).count ?? 0 > 5 {
            self.nextView.backgroundColor = UIColor.black
        } else {
            self.nextView.backgroundColor = UIColor(red: 0, green: 0, blue: 0, alpha: 0.6)
        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillDisappear), name: UIResponder.keyboardWillHideNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillAppear), name: UIResponder.keyboardWillShowNotification, object: nil)
    }
    
    @objc func keyboardWillDisappear() {
        
        self.updateButtonColor()
        
        self.codeButton.alpha = 1
        
        NSLayoutConstraint.deactivate([self.contentViewBottom])
        self.contentViewBottom = NSLayoutConstraint(item: self.contentView!, attribute: .bottom, relatedBy: .equal, toItem: self.scrollView, attribute: .bottom, multiplier: 1, constant: 0)
        NSLayoutConstraint.activate([self.contentViewBottom])
        
        self.view.layoutIfNeeded()
    }
    
    @objc func keyboardWillAppear(_ notification:Notification) {
        
        if let keyboardSize = (notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue {
            
            let keyboardHeight = keyboardSize.height
            
            NSLayoutConstraint.deactivate([self.contentViewBottom])
            self.contentViewBottom = NSLayoutConstraint(item: self.contentView!, attribute: .bottom, relatedBy: .equal, toItem: self.scrollView, attribute: .bottom, multiplier: 1, constant: -keyboardHeight)
            NSLayoutConstraint.activate([self.contentViewBottom])
            
            self.view.layoutIfNeeded()
        }
    }
    
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        self.updateButtonColor()
        
        // If code field is active and confirm button is enabled, trigger confirmation
        if textField == self.codeTextField && self.nextView.backgroundColor == UIColor.black {
            self.nextButtonTapped(UIButton())
            return true
        }
        
        return false
    }
    
    func textFieldDidEndEditing(_ textField: UITextField) {
        self.updateButtonColor()
    }
    
    func textFieldDidChangeSelection(_ textField: UITextField) {
        self.updateButtonColor()
        
        // Check if we should auto-trigger after text changes
        if textField == self.codeTextField {
            let trimmedText = textField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            
            if trimmedText.count >= 6 && self.nextView.backgroundColor == UIColor.black && !self.hasAutoTriggered {
                self.hasAutoTriggered = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.nextButtonTapped(UIButton())
                }
            }
        }
    }
    
    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        self.updateButtonColor()
        
        // Auto-trigger when 6 digits are entered
        if textField == self.codeTextField {
            let currentText = textField.text ?? ""
            let newText = (currentText as NSString).replacingCharacters(in: range, with: string)
            let trimmedText = newText.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // If we have 6 or more digits and the button is enabled, auto-trigger
            if trimmedText.count >= 6 && self.nextView.backgroundColor == UIColor.black && !self.hasAutoTriggered {
                self.hasAutoTriggered = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.nextButtonTapped(UIButton())
                }
            }
        }
        
        return true
    }
    
    @IBAction func backgroundButtonTapped(_ sender: UIButton) {
        self.view.endEditing(true)
    }
    
    @objc func askForPushNotifications() {
        
        self.hideAlert()
        
        let current = UNUserNotificationCenter.current()
        current.getNotificationSettings { (settings) in
            
            if settings.authorizationStatus == .notDetermined {
                // User hasn't set their preference yet.
                
                current.delegate = self
                current.requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
                    
                    print("Permission granted: \(granted)")
                    guard granted else {
                        self.check2Fa()
                        return
                    }
                    
                    // Double check that the preference is now authorized.
                    current.getNotificationSettings { (settings) in
                        print("Notification settings: \(settings)")
                        guard settings.authorizationStatus == .authorized else {
                            self.check2Fa()
                            return
                        }
                        DispatchQueue.main.async {
                            // Register for notifications.
                            self.start2Fa = true
                            UIApplication.shared.registerForRemoteNotifications()
                        }
                    }
                }
            } else if settings.authorizationStatus == .authorized {
                // User has already authorized notifications.
                DispatchQueue.main.async {
                    // Register for notifications.
                    self.start2Fa = true
                    UIApplication.shared.registerForRemoteNotifications()
                }
            }
        }
    }
    
    func changeColors() {
        
        self.topLabel.textColor = Colors.getColor("blackorwhite")
        
        if CacheManager.darkModeIsOn() {
            self.resendLabel.textColor = Colors.getColor("blackorwhite")
        } else {
            self.resendLabel.textColor = Colors.getColor("transparentblack")
        }

    }
    
    func setWords() {
        
        self.topLabel.text = Language.getWord(withID: "youvegotmail")
        self.codeTextField.placeholder = Language.getWord(withID: "entercode")
        self.nextButtonLabel.text = Language.getWord(withID: "confirm")
        self.resendLabel.text = Language.getWord(withID: "resendcode")
    }
    
}
