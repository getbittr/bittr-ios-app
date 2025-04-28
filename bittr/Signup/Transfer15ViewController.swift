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
    
    var currentClientID = ""
    var currentIbanID = ""
    
    @IBOutlet weak var nextButtonLabel: UILabel!
    @IBOutlet weak var nextButtonActivityIndicator: UIActivityIndicatorView!
    
    var counter = 0
    
    var setSender = ""
    var start2Fa = false
    var coreVC:CoreViewController?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Corner radii and button titles.
        codeView.layer.cornerRadius = 13
        nextView.layer.cornerRadius = 13
        codeButton.setTitle("", for: .normal)
        nextButton.setTitle("", for: .normal)
        resendButton.setTitle("", for: .normal)
        backgroundButton.setTitle("", for: .normal)
        backgroundButton2.setTitle("", for: .normal)
        
        // Email code text field.
        codeTextField.delegate = self
        codeTextField.addDoneButton(target: self, returnaction: #selector(self.doneButtonTapped))
        
        // Notification observers.
        NotificationCenter.default.addObserver(self, selector: #selector(updateClient), name: NSNotification.Name(rawValue: "signupnext"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(resume2Fa), name: NSNotification.Name(rawValue: "resume2fa"), object: nil)
        
        self.changeColors()
        self.setWords()
    }
    
    @objc func updateClient(notification:NSNotification) {
        // Register client details.
        if let userInfo = notification.userInfo as [AnyHashable:Any]? {
            if let clientID = userInfo["client"] as? String {
                self.currentClientID = clientID
            }
            if let ibanID = userInfo["iban"] as? String {
                self.currentIbanID = ibanID
            }
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
        updateButtonColor()
        if self.nextView.backgroundColor == UIColor.black {
            
            self.nextButtonLabel.alpha = 0
            self.nextButtonActivityIndicator.startAnimating()
            
            // Check push notifications status.
            let current = UNUserNotificationCenter.current()
            current.getNotificationSettings { (settings) in
                
                self.setSender = sender.accessibilityIdentifier!
                
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
        
        print("Check 2FA started.")
        
        var envKey = "proddevice"
        if UserDefaults.standard.value(forKey: "envkey") as? Int == 0 {
            envKey = "device"
        }
        
        let deviceDict = UserDefaults.standard.value(forKey: envKey) as? NSDictionary
        if let actualDeviceDict = deviceDict {
            // Some device information exists.
            let clients:[Client] = CacheManager.parseDevice(deviceDict: actualDeviceDict)
            
            for client in clients {
                if client.id == self.currentClientID {
                    
                    for iban in client.ibanEntities {
                        if iban.id == self.currentIbanID {
                            
                            // Send email and verification code to bittr API.
                            let parameters: [String: Any] = [
                                "email_address": iban.yourEmail,
                                "token_2fa": self.codeTextField.text!.trimmingCharacters(in: .whitespacesAndNewlines)
                            ]
                            
                            // TODO: Public?
                            var envUrl = "https://getbittr.com/api/verify/email/check2fa"
                            if UserDefaults.standard.value(forKey: "envkey") as? Int == 0 {
                                envUrl = "https://model-arachnid-viable.ngrok-free.app/verify/email/check2fa"
                            }
                            
                            Task {
                                await CallsManager.makeApiCall(url: envUrl, parameters: parameters, getOrPost: "POST") { result in
                                    
                                    switch result {
                                    case .success(let receivedDictionary):
                                        let emailToken = receivedDictionary["token"]
                                        let errorMessage = receivedDictionary["message"]
                                        if let actualEmailToken = emailToken as? String {
                                            // Email address verified. Store email token in cache.
                                            CacheManager.addEmailToken(clientID: self.currentClientID, ibanID: self.currentIbanID, emailToken: actualEmailToken)
                                            
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
            }
        }
    }
    
    
    func getAddress(page:String) {
        
        var envKey = "proddevice"
        if UserDefaults.standard.value(forKey: "envkey") as? Int == 0 {
            envKey = "device"
        }
        
        let deviceDict = UserDefaults.standard.value(forKey: envKey) as? NSDictionary
        if let actualDeviceDict = deviceDict {
            // Some device information exists.
            let clients:[Client] = CacheManager.parseDevice(deviceDict: actualDeviceDict)
            for client in clients {
                if client.id == self.currentClientID {
                    for iban in client.ibanEntities {
                        if iban.id == self.currentIbanID {
                            
                            let message = "I confirm I'm the sole owner of the bitcoin address I provided and I will be sending my own funds to bittr. Order: \(iban.emailToken.prefix(32)). IBAN: \(iban.yourIbanNumber)"
                            let parameters = ["message": message]
                            
                            self.createClient(message: message, page: page, iban: iban)
                        }
                    }
                }
            }
        }
    }
    
    
    func createClient(message:String, page:String, iban:IbanEntity) {
        
        Task {
            // Get real onchain address.
            let wallet = LightningNodeService.shared.getWallet()
            let firstAddress = try wallet?.getAddress(addressIndex: AddressIndex.peek(index: 0)).address.asString()
            
            // Send to Bittr.
            self.createBittrAccount(receivedAddress: firstAddress ?? "", message: message, page: page, iban: iban)
        }
    }
    
    
    func createBittrAccount(receivedAddress:String, message:String, page:String, iban:IbanEntity) {
        
        let lightningPubKey = LightningNodeService.shared.nodeId()
        let xpub = LightningNodeService.shared.getXpub()
        
        let signature = try! LightningNodeService.shared.signMessageForPath(path: "m/84'/1'/0'/0/0", message: message)
        
        Task {
            do {
                let lightningSignature = try await LightningNodeService.shared.signMessage(message: message)
                
                // TODO: Public?
                let parameters: [String: Any] = [
                    "email": iban.yourEmail,
                    "email_token": iban.emailToken,
                    "bitcoin_address": receivedAddress,
                    "initial_address_type": "extended",
                    "category": "ledger",
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
                
                // TODO: Public?
                var envUrl = "https://getbittr.com/api/customer"
                if UserDefaults.standard.value(forKey: "envkey") as? Int == 0 {
                    envUrl = "https://model-arachnid-viable.ngrok-free.app/customer"
                }
                
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
                                    CacheManager.addBittrIban(clientID: self.currentClientID, ibanID: self.currentIbanID, ourIban: actualDataOurIban, ourSwift: actualDataSwift, yourCode: actualDataCode)
                                    self.nextButtonActivityIndicator.stopAnimating()
                                    self.nextButtonLabel.alpha = 1
                                    // Move to next page.
                                    let notificationDict:[String: Any] = ["page":page, "client":self.currentClientID, "iban":self.currentIbanID, "code":true]
                                     NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "signupnext"), object: nil, userInfo: notificationDict) as Notification)
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
        let notificationDict:[String: Any] = ["page":"6"]
        NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "signupnext"), object: nil, userInfo: notificationDict) as Notification)
    }
    
    
    @IBAction func resendCodeButtonTapped(_ sender: UIButton) {
        
        // User can request a new email verification code every 30 seconds.
        
        if self.counter == 0 {
            
            var envKey = "proddevice"
            if UserDefaults.standard.value(forKey: "envkey") as? Int == 0 {
                envKey = "device"
            }
            
            // Prompt bittr API to send new verification code to email address.
            let deviceDict = UserDefaults.standard.value(forKey: envKey) as? NSDictionary
            if let actualDeviceDict = deviceDict {
                let clients:[Client] = CacheManager.parseDevice(deviceDict: actualDeviceDict)
                for client in clients {
                    if client.id == self.currentClientID {
                        for iban in client.ibanEntities {
                            if iban.id == self.currentIbanID {
                                
                                let parameters: [String: Any] = [
                                    "email": iban.yourEmail,
                                    "category": "ledger"
                                ]
                                
                                // TODO: Public?
                                var envUrl = "https://getbittr.com/api/verify/email"
                                if UserDefaults.standard.value(forKey: "envkey") as? Int == 0 {
                                    envUrl = "https://model-arachnid-viable.ngrok-free.app/verify/email"
                                }
                                
                                Task {
                                    await CallsManager.makeApiCall(url: envUrl, parameters: parameters, getOrPost: "POST") { result in
                                        
                                        switch result {
                                        case .failure(let error):
                                            DispatchQueue.main.async {
                                                self.showAlert(presentingController: self, title: Language.getWord(withID: "oops"), message: Language.getWord(withID: "bittrsignupfail4"), buttons: [Language.getWord(withID: "okay")], actions: nil)
                                                SentrySDK.capture(error: error)
                                            }
                                        case .success(let receivedDictionary):
                                            DispatchQueue.main.async {
                                                let alert = UIAlertController(title: Language.getWord(withID: "emailresent"), message: "\(Language.getWord(withID: "emailresent2")) \(iban.yourEmail).", preferredStyle: .alert)
                                                alert.addAction(UIAlertAction(title: Language.getWord(withID: "okay"), style: .cancel, handler: nil))
                                                alert.addAction(UIAlertAction(title: Language.getWord(withID: "changeemail"), style: .default, handler: {_ in
                                                    let notificationDict:[String: Any] = ["page":"6"]
                                                    NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "signupnext"), object: nil, userInfo: notificationDict) as Notification)
                                                }))
                                                self.present(alert, animated: true)
                                                
                                                // Restart counter.
                                                self.counter = 30
                                                Timer.scheduledTimer(timeInterval: 1.0, target: self, selector: #selector(self.updateCounter), userInfo: nil, repeats: true)
                                            }
                                        }
                                        
                                    }
                                }
                            }
                        }
                    }
                }
            }
        } else {
            // Timer is still counting down.
            let alert = UIAlertController(title: "", message: Language.getWord(withID: "resendcode2"), preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: Language.getWord(withID: "okay"), style: .cancel, handler: nil))
            alert.addAction(UIAlertAction(title: Language.getWord(withID: "changeemail"), style: .default, handler: {_ in
                let notificationDict:[String: Any] = ["page":"6"]
                NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "signupnext"), object: nil, userInfo: notificationDict) as Notification)
            }))
            self.present(alert, animated: true)
        }
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
        
        updateButtonColor()
        
        self.codeButton.alpha = 1
        
        NSLayoutConstraint.deactivate([contentViewBottom])
        contentViewBottom = NSLayoutConstraint(item: contentView!, attribute: .bottom, relatedBy: .equal, toItem: scrollView, attribute: .bottom, multiplier: 1, constant: 0)
        NSLayoutConstraint.activate([contentViewBottom])
        
        self.view.layoutIfNeeded()
    }
    
    @objc func keyboardWillAppear(_ notification:Notification) {
        
        if let keyboardSize = (notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue {
            
            let keyboardHeight = keyboardSize.height
            
            NSLayoutConstraint.deactivate([contentViewBottom])
            contentViewBottom = NSLayoutConstraint(item: contentView!, attribute: .bottom, relatedBy: .equal, toItem: scrollView, attribute: .bottom, multiplier: 1, constant: -keyboardHeight)
            NSLayoutConstraint.activate([contentViewBottom])
            
            self.view.layoutIfNeeded()
        }
    }
    
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        updateButtonColor()
        return false
    }
    
    func textFieldDidEndEditing(_ textField: UITextField) {
        updateButtonColor()
    }
    
    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        updateButtonColor()
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
