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
                if settings.authorizationStatus == .notDetermined {
                    // Notifications preference hasn't been set yet.
                    DispatchQueue.main.async {
                        let alert = UIAlertController(title: Language.getWord(withID: "receivenotifications"), message: Language.getWord(withID: "receivenotifications2"), preferredStyle: .alert)
                        alert.addAction(UIAlertAction(title: Language.getWord(withID: "okay"), style: .cancel, handler: {_ in
                            self.askForPushNotifications(sender: sender.accessibilityIdentifier!)
                        }))
                        self.present(alert, animated: true)
                    }
                } else if settings.authorizationStatus == .authorized, CacheManager.getRegistrationToken() == nil {
                    // Notifications preference has been set but token hasn't been cached.
                    self.askForPushNotifications(sender: sender.accessibilityIdentifier!)
                } else {
                    self.check2Fa(sender: sender.accessibilityIdentifier!)
                }
            }
        }
    }
    
    
    @objc func resume2Fa() {
        if start2Fa == true {
            self.check2Fa(sender: self.setSender)
            self.start2Fa = false
        }
    }
    
    func check2Fa(sender:String) {
        
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
                            let parameters = [
                              [
                                "key": "email_address",
                                "value": iban.yourEmail,
                                "type": "text"
                              ],
                              [
                                "key": "token_2fa",
                                "value": self.codeTextField.text!.trimmingCharacters(in: .whitespacesAndNewlines),
                                "type": "text"
                              ]] as [[String : Any]]
                            
                            let boundary = "Boundary-\(UUID().uuidString)"
                            var body = ""
                            var error: Error? = nil
                            for param in parameters {
                                if param["disabled"] == nil {
                                    let paramName = param["key"]!
                                    body += "--\(boundary)\r\n"
                                    body += "Content-Disposition:form-data; name=\"\(paramName)\""
                                    if param["contentType"] != nil {
                                        body += "\r\nContent-Type: \(param["contentType"] as! String)"
                                    }
                                    let paramType = param["type"] as! String
                                    if paramType == "text" {
                                        let paramValue = param["value"] as! String
                                        body += "\r\n\r\n\(paramValue)\r\n"
                                    }
                                }
                            }
                            body += "--\(boundary)--\r\n";
                            let postData = body.data(using: .utf8)
                            
                            // TODO: Public?
                            var envUrl = "https://getbittr.com/api/verify/email/check2fa"
                            if UserDefaults.standard.value(forKey: "envkey") as? Int == 0 {
                                envUrl = "https://staging.getbittr.com/api/verify/email/check2fa"
                            }
                            
                            var request = URLRequest(url: URL(string: envUrl)!,timeoutInterval: Double.infinity)
                            request.addValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
                            request.httpMethod = "POST"
                            request.httpBody = postData
                            
                            let task = URLSession.shared.dataTask(with: request) { data, response, error in
                                guard let data = data else {
                                    print(String(describing: error))
                                    DispatchQueue.main.async {
                                        if let actualError = error {
                                            SentrySDK.capture(error: actualError)
                                        }
                                    }
                                    return
                                }
                                
                                // Data has been received from bittr API.
                                
                                //print(String(data: data, encoding: .utf8)!)
                                
                                var dataDictionary:NSDictionary?
                                if let receivedData = String(data: data, encoding: .utf8)?.data(using: String.Encoding.utf8) {
                                    
                                    do {
                                        dataDictionary = try JSONSerialization.jsonObject(with: receivedData, options: []) as? NSDictionary
                                        if let actualDataDict = dataDictionary {
                                            let emailToken = actualDataDict["token"]
                                            let errorMessage = actualDataDict["message"]
                                            if let actualEmailToken = emailToken as? String {
                                                // Email address verified. Store email token in cache.
                                                CacheManager.addEmailToken(clientID: self.currentClientID, ibanID: self.currentIbanID, emailToken: actualEmailToken)
                                                
                                                DispatchQueue.main.async {
                                                    // Get wallet address.
                                                    self.getAddress(page: sender)
                                                }
                                            } else if let actualErrorMessage = errorMessage as? String {
                                                if actualErrorMessage == "Invalid 2FA verification token provided" {
                                                    DispatchQueue.main.async {
                                                        self.nextButtonActivityIndicator.stopAnimating()
                                                        self.nextButtonLabel.alpha = 1
                                                        self.showAlert(Language.getWord(withID: "oops"), Language.getWord(withID: "verificationfail"), Language.getWord(withID: "okay"))
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
                            task.resume()
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
        
        Task {
            do {
                let lightningSignature = try await LightningNodeService.shared.signMessage(message: message)
                
                // TODO: Public?
                var parameters: [String: Any] = [
                    "email": iban.yourEmail,
                    "email_token": iban.emailToken,
                    "bitcoin_address": receivedAddress,
                    "initial_address_type": "extended",
                    "category": "ledger",
                    "bitcoin_message": message,
                    "bitcoin_signature": "Hxzhjz3+eMJNjhJc6iyWJfvD3c/ukn3ygpwW0EfY/KKXaNNwAe0Syis7GxGCTtieui8g7CYg39+nuT55Lb0QYms=",
                    "iban": iban.yourIbanNumber,
                    "lightning_pubkey": lightningPubKey,
                    "lightning_signature": lightningSignature,
                    "xpub_key": xpub,
                    "xpub_addr_type": "bech32",
                    "xpub_path": "m/0/x",
                    "skip_xpub_usage_check": "true",
                    "ios_device_token": CacheManager.getRegistrationToken() ?? ""
                ]
                
                do {
                    // Send to bittr API for signup.
                    let postData = try JSONSerialization.data(withJSONObject: parameters, options: [])
                    
                    // TODO: Public?
                    var envUrl = "https://getbittr.com/api/customer"
                    if UserDefaults.standard.value(forKey: "envkey") as? Int == 0 {
                        envUrl = "https://staging.getbittr.com/api/customer"
                    }
                    
                    var request = URLRequest(url: URL(string: envUrl)!,timeoutInterval: Double.infinity)
                    request.addValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.httpMethod = "POST"
                    request.httpBody = postData
                    
                    let task = URLSession.shared.dataTask(with: request) { data, response, error in
                        guard let data = data else {
                            DispatchQueue.main.async {
                                print(String(describing: error))
                                self.showAlert(Language.getWord(withID: "oops"), Language.getWord(withID: "bittrsignupfail"), Language.getWord(withID: "okay"))
                                if let actualError = error {
                                    SentrySDK.capture(error: actualError)
                                }
                            }
                            return
                        }
                        
                        // Response has been received from bittr API.
                        
                        //print(String(data: data, encoding: .utf8)!)
                        
                        var dataDictionary:NSDictionary?
                        if let receivedData = String(data: data, encoding: .utf8)?.data(using: String.Encoding.utf8) {
                            do {
                                dataDictionary = try JSONSerialization.jsonObject(with: receivedData, options: []) as? NSDictionary
                                if let actualDataDict = dataDictionary {
                                    if let actualDataItems = actualDataDict["data"] as? NSDictionary {
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
                                    } else if let actualApiMessage = actualDataDict["message"] as? String {
                                        // Some message has been received.
                                        DispatchQueue.main.async {
                                            if actualApiMessage == "Unable to create customer account (invalid iban)" {
                                                self.nextButtonActivityIndicator.stopAnimating()
                                                self.nextButtonLabel.alpha = 1
                                                self.codeTextField.text = nil
                                                let alert = UIAlertController(title: Language.getWord(withID: "oops"), message: Language.getWord(withID: "bittrsignupfail2"), preferredStyle: .alert)
                                                alert.addAction(UIAlertAction(title: Language.getWord(withID: "okay"), style: .cancel, handler: {_ in
                                                    let notificationDict:[String: Any] = ["page":"6"]
                                                     NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "signupnext"), object: nil, userInfo: notificationDict) as Notification)
                                                }))
                                                self.present(alert, animated: true)
                                            } else {
                                                self.nextButtonActivityIndicator.stopAnimating()
                                                self.nextButtonLabel.alpha = 1
                                                self.codeTextField.text = nil
                                                let alert = UIAlertController(title: Language.getWord(withID: "oops"), message: "\(Language.getWord(withID: "bittrsignupfail3")) (\(actualApiMessage).)", preferredStyle: .alert)
                                                alert.addAction(UIAlertAction(title: Language.getWord(withID: "okay"), style: .cancel, handler: {_ in
                                                    let notificationDict:[String: Any] = ["page":"6"]
                                                     NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "signupnext"), object: nil, userInfo: notificationDict) as Notification)
                                                }))
                                                self.present(alert, animated: true)
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
                    task.resume()
                } catch let error as NSError {
                    print(error)
                    DispatchQueue.main.async {
                        SentrySDK.capture(error: error)
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
                                
                                let parameters = [
                                  [
                                    "key": "email",
                                    "value": iban.yourEmail,
                                    "type": "text"
                                  ],
                                  [
                                    "key": "category",
                                    "value": "ledger",
                                    "type": "text"
                                  ]] as [[String : Any]]
                                
                                let boundary = "Boundary-\(UUID().uuidString)"
                                var body = ""
                                var error: Error? = nil
                                for param in parameters {
                                    if param["disabled"] == nil {
                                        let paramName = param["key"]!
                                        body += "--\(boundary)\r\n"
                                        body += "Content-Disposition:form-data; name=\"\(paramName)\""
                                        if param["contentType"] != nil {
                                            body += "\r\nContent-Type: \(param["contentType"] as! String)"
                                        }
                                        let paramType = param["type"] as! String
                                        if paramType == "text" {
                                            let paramValue = param["value"] as! String
                                            body += "\r\n\r\n\(paramValue)\r\n"
                                        }
                                    }
                                }
                                body += "--\(boundary)--\r\n";
                                let postData = body.data(using: .utf8)
                                
                                // TODO: Public?
                                var envUrl = "https://getbittr.com/api/verify/email"
                                if UserDefaults.standard.value(forKey: "envkey") as? Int == 0 {
                                    envUrl = "https://staging.getbittr.com/api/verify/email"
                                }
                                
                                var request = URLRequest(url: URL(string: envUrl)!,timeoutInterval: Double.infinity)
                                request.addValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
                                request.httpMethod = "POST"
                                request.httpBody = postData
                                let task = URLSession.shared.dataTask(with: request) { data, response, error in
                                    guard let data = data else {
                                        print(String(describing: error))
                                        DispatchQueue.main.async {
                                            self.showAlert(Language.getWord(withID: "oops"), Language.getWord(withID: "bittrsignupfail4"), Language.getWord(withID: "okay"))
                                            if let actualError = error {
                                                SentrySDK.capture(error: actualError)
                                            }
                                        }
                                        return
                                    }
                                    
                                    // Response received from bittr API.
                                    
                                    //print(String(data: data, encoding: .utf8)!)
                                    
                                    DispatchQueue.main.async {
                                        let alert = UIAlertController(title: Language.getWord(withID: "emailresent"), message: "\(Language.getWord(withID: "emailresent2")) \(iban.yourEmail).", preferredStyle: .alert)
                                        alert.addAction(UIAlertAction(title: Language.getWord(withID: "okay"), style: .cancel, handler: nil))
                                        alert.addAction(UIAlertAction(title: Language.getWord(withID: "changeemail"), style: .default, handler: {_ in
                                            let notificationDict:[String: Any] = ["page":"6"]
                                            NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "signupnext"), object: nil, userInfo: notificationDict) as Notification)
                                        }))
                                        self.present(alert, animated: true)
                                    }
                                }
                                task.resume()
                                
                                // Restart counter.
                                self.counter = 30
                                Timer.scheduledTimer(timeInterval: 1.0, target: self, selector: #selector(updateCounter), userInfo: nil, repeats: true)
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
    
    func askForPushNotifications(sender:String) {
        
        let current = UNUserNotificationCenter.current()
        current.getNotificationSettings { (settings) in
            
            if settings.authorizationStatus == .notDetermined {
                // User hasn't set their preference yet.
                
                current.delegate = self
                current.requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
                    
                    print("Permission granted: \(granted)")
                    guard granted else {
                        self.check2Fa(sender: sender)
                        return
                    }
                    
                    // Double check that the preference is now authorized.
                    current.getNotificationSettings { (settings) in
                        print("Notification settings: \(settings)")
                        guard settings.authorizationStatus == .authorized else {
                            self.check2Fa(sender: sender)
                            return
                        }
                        DispatchQueue.main.async {
                            // Register for notifications.
                            self.start2Fa = true
                            self.setSender = sender
                            UIApplication.shared.registerForRemoteNotifications()
                        }
                    }
                }
            } else if settings.authorizationStatus == .authorized {
                // User has already authorized notifications.
                DispatchQueue.main.async {
                    // Register for notifications.
                    self.start2Fa = true
                    self.setSender = sender
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
