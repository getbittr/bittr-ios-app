//
//  Transfer2ViewController.swift
//  bittr
//
//  Created by Tom Melters on 15/06/2023.
//

import UIKit
import UserNotifications

class Transfer2ViewController: UIViewController, UITextFieldDelegate, UNUserNotificationCenterDelegate {
    
    // User has received code in email. Send this code to the bittr API.
    
    // UI elements
    @IBOutlet weak var topLabel: UILabel!
    @IBOutlet weak var codeView: UIView!
    @IBOutlet weak var codeTextField: UITextField!
    @IBOutlet weak var codeButton: UIButton!
    @IBOutlet weak var resendButton: UIButton!
    @IBOutlet weak var resendLabel: UILabel!
    
    // Scroll view and background buttons
    @IBOutlet weak var scrollView: UIScrollView!
    @IBOutlet weak var contentView: UIView!
    @IBOutlet weak var contentViewBottom: NSLayoutConstraint!
    @IBOutlet weak var centerCard: UIView!
    @IBOutlet weak var backgroundButton2: UIButton!
    @IBOutlet weak var backgroundButton: UIButton!
    
    // Next button
    @IBOutlet weak var nextView: UIView!
    @IBOutlet weak var nextButton: UIButton!
    @IBOutlet weak var nextButtonArrow: UIImageView!
    @IBOutlet weak var nextButtonLabel: UILabel!
    @IBOutlet weak var nextButtonActivityIndicator: UIActivityIndicatorView!
    
    // Timer
    var counter = 0
    
    // Variables
    var start2Fa = false
    var hasAutoTriggered = false
    var notificationsDenied = false
    var coreVC:CoreViewController?
    var signupVC:SignupViewController?
    var ibanVC:RegisterIbanViewController?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Corner radii
        self.codeView.layer.cornerRadius = 8
        self.nextView.layer.cornerRadius = 8
        self.centerCard.layer.cornerRadius = 13
        self.centerCard.setShadow()
        
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
        NotificationCenter.default.addObserver(self, selector: #selector(resume2Fa), name: NSNotification.Name(rawValue: "receivedToken"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(tokenRegistrationFailed), name: NSNotification.Name(rawValue: "tokenRegistrationFailed"), object: nil)
        
        self.topLabel.accessibilityIdentifier = TestID.Signup.Bittr.Otp.topLabel
        self.codeTextField.accessibilityIdentifier = TestID.Signup.Bittr.Otp.codeTextField
        self.codeButton.accessibilityIdentifier = TestID.Signup.Bittr.Otp.codeButton
        self.resendButton.accessibilityIdentifier = TestID.Signup.Bittr.Otp.resendButton
        self.nextButton.accessibilityIdentifier = TestID.Signup.Bittr.Otp.nextButton

        // Set language and colors.
        self.changeColors()
        self.setWords()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        self.triggerOtpAutoFocus()
    }
    
    func triggerOtpAutoFocus() {
        // Auto-focus on OTP field when triggered from previous page
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.codeTextField.becomeFirstResponder()
            self.codeButton.alpha = 0
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
        self.updateButtonColor()
        
        if self.nextView.backgroundColor == UIColor.black {
            // Field has been filled.
            self.nextButtonLabel.alpha = 0
            self.nextButtonArrow.alpha = 0
            self.nextButtonActivityIndicator.startAnimating()
            self.checkPushNotificationStatus()
        } else {
            // Field has not been filled.
            self.showAlert(title: Language.getWord(withID: "oops"), message: Language.getWord(withID: "transfer15vc"), buttons: [.dismiss(Language.getWord(withID: "okay"))])
        }
    }
    
    func checkPushNotificationStatus() {
        
        // Check push notifications status.
        let current = UNUserNotificationCenter.current()
        current.getNotificationSettings { (settings) in
            
            if settings.authorizationStatus == .notDetermined {
                // Notifications preference hasn't been set yet.
                DispatchQueue.main.async {
                    self.showAlert(title: Language.getWord(withID: "receivenotifications"), message: Language.getWord(withID: "receivenotifications2"), buttons: [.action(Language.getWord(withID: "okay")) { self.askForPushNotifications() }])
                }
            } else if settings.authorizationStatus != .authorized {
                // Notifications have been rejected. The user can still continue —
                // their purchases just get paid out on-chain instead of via lightning.
                DispatchQueue.main.async {
                    self.showAlert(title: Language.getWord(withID: "receivenotifications"), message: Language.getWord(withID: "receivenotifications3"), buttons: [.action(Language.getWord(withID: "cancel")) { self.cancelLoading() }, .action(Language.getWord(withID: "continue")) { self.proceedWithoutNotifications() }])
                }
            } else if CacheManager.getRegistrationToken() == nil {
                Log.info("Notifications preference has been set but token hasn't been cached.")
                DispatchQueue.main.async {
                    self.askForPushNotifications()
                }
            } else {
                // getNotificationSettings' completion runs on a background queue;
                // sendCodeToBittr reads codeTextField.text, so it must be on main.
                DispatchQueue.main.async {
                    self.sendCodeToBittr()
                }
            }
        }
    }
    
    
    func cancelLoading() {
        DispatchQueue.main.async {
            self.nextButtonLabel.alpha = 1
            self.nextButtonArrow.alpha = 1
            self.nextButtonActivityIndicator.stopAnimating()
        }
    }


    func proceedWithoutNotifications() {
        // User chose to continue without push notifications. Flag it so that
        // gatherParameters registers them with on-chain payouts, then carry on
        // with signup (the Next-button spinner keeps running).
        self.notificationsDenied = true
        self.sendCodeToBittr()
    }
    
    
    @objc func resume2Fa() {
        if self.start2Fa {
            self.sendCodeToBittr()
            self.start2Fa = false
        }
    }

    // Each token wait gets a generation so a stale deadline (from an earlier
    // attempt) can't fire into a newer one.
    private static var tokenWaitGeneration = 0

    /// Arm a deadline on the wait for didRegisterForRemoteNotificationsWith-
    /// DeviceToken. Registration is allowed to never call back (no APNS
    /// connectivity, wedged simulator push daemon, flaky network), and
    /// without a deadline the Next-button spinner spins forever with no way
    /// out. After 15s of silence, fail the same way an explicit registration
    /// failure does.
    func startTokenRegistrationTimeout() {
        Transfer2ViewController.tokenWaitGeneration += 1
        let generation = Transfer2ViewController.tokenWaitGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in
            guard let self = self,
                  generation == Transfer2ViewController.tokenWaitGeneration,
                  self.start2Fa else { return }
            Log.info("Timed out waiting for the device token.")
            self.tokenRegistrationFailed()
        }
    }

    /// Token registration failed (didFailToRegister… fired, or the deadline
    /// above expired). Stop the spinner and offer the same choice as the
    /// denied-permission path: retry, or continue with on-chain payouts.
    @objc func tokenRegistrationFailed() {
        guard self.start2Fa else { return }
        self.start2Fa = false
        DispatchQueue.main.async {
            self.cancelLoading()
            self.showAlert(title: Language.getWord(withID: "receivenotifications"), message: Language.getWord(withID: "tokenregistrationfail"), buttons: [.action(Language.getWord(withID: "tryagain")) { self.askForPushNotifications() }, .action(Language.getWord(withID: "continue")) { self.proceedWithoutNotifications() }])
        }
    }
    
    func sendCodeToBittr() {
        Log.info("Will send code to bittr.")
        
        // Get current IBAN ID.
        let currentIbanID = self.signupVC?.currentIbanID ?? self.ibanVC!.currentIbanID
        for (index, eachIbanEntity) in BitcoinManager.shared.bittrWallet.ibanEntities.enumerated() {
            if eachIbanEntity.id == currentIbanID {
                Log.info("Did fetch correct IBAN entity.")

                // Send email and verification code to bittr API.
                // Include the lightning node pubkey so the backend can recognise a
                // returning customer (recovery): the restore fields (deposit_code +
                // original signed message) are only returned when BOTH the email and
                // the pubkey match an existing record. If the node isn't up yet we omit
                // it and the backend treats this as a new registration.
                var parameters: [String: Any] = [
                    "email_address": eachIbanEntity.yourEmail,
                    "token_2fa": self.codeTextField.text!.trimmingCharacters(in: .whitespacesAndNewlines)
                ]
                if let lightningPubKey = BitcoinManager.shared.nodeId() {
                    parameters["lightning_pubkey"] = lightningPubKey
                }
                
                let envUrl = "\(EnvironmentConfig.bittrAPIBaseURL)/verify/email/check2fa"
                
                Task {
                    await CallsManager.makeApiCall(url: envUrl, parameters: parameters, getOrPost: .post) { result in
                        
                        DispatchQueue.main.async {
                            // Stop animating.
                            self.nextButtonActivityIndicator.stopAnimating()
                            self.nextButtonLabel.alpha = 1
                            self.nextButtonArrow.alpha = 1
                            
                            // Check result.
                            switch result {
                            case .success(let receivedDictionary):
                                let emailToken = receivedDictionary["token"]
                                let errorMessage = receivedDictionary["message"]
                                if let actualEmailToken = emailToken as? String {
                                    // Email address verified. Store email token in cache.
                                    CacheManager.addEmailToken(ibanID: eachIbanEntity.id, emailToken: actualEmailToken)
                                    
                                    // Update the in-memory IBAN entity with the new email token
                                    BitcoinManager.shared.bittrWallet.ibanEntities[index].emailToken = actualEmailToken

                                    // Recovery: a returning customer (email + pubkey matched) gets back
                                    // their existing deposit code and the original signed message. When
                                    // both are present we reuse the deposit code and sign that message
                                    // verbatim instead of rebuilding it.
                                    let restoreDepositCode = receivedDictionary["deposit_code"] as? String
                                    let restoreMessage = receivedDictionary["message"] as? String

                                    // Get wallet address.
                                    self.gatherParameters(ibanEntity: eachIbanEntity, restoreDepositCode: restoreDepositCode, restoreMessage: restoreMessage)
                                } else if let actualErrorMessage = errorMessage as? String {
                                    if actualErrorMessage == "Invalid 2FA verification token provided" {
                                        self.showAlert(title: Language.getWord(withID: "oops"), message: Language.getWord(withID: "verificationfail"), buttons: [.dismiss(Language.getWord(withID: "okay"))])
                                    } else {
                                        self.showAlert(title: Language.getWord(withID: "oops"), message: Language.getWord(withID: "transfer15vc2").replacingOccurrences(of: "<error>", with: actualErrorMessage), buttons: [.dismiss(Language.getWord(withID: "okay"))])
                                    }
                                } else {
                                    self.showAlert(title: Language.getWord(withID: "oops"), message: Language.getWord(withID: "transfer15vc2").replacingOccurrences(of: "<error>", with: "unavailable."), buttons: [.dismiss(Language.getWord(withID: "okay"))])
                                }
                            case .failure(let error):
                                SentryManager.capture(error, context: "Transfer2ViewController row 178")
                                self.showAlert(title: Language.getWord(withID: "oops"), message: Language.getWord(withID: "verificationfail"), buttons: [.dismiss(Language.getWord(withID: "okay"))])
                            }
                        }
                    }
                }
            }
        }
    }
    
    
    func gatherParameters(ibanEntity:IbanEntity, restoreDepositCode: String? = nil, restoreMessage: String? = nil) {

        // Generate message and signature.
        // On recovery, sign the backend's stored registration message verbatim — do NOT
        // rebuild it. The IBAN embedded in that message may differ from the IBAN being
        // submitted now (the backend verifies the signature against the stored message
        // but persists the new IBAN), so rebuilding would break signature verification.
        let message = restoreMessage ?? "I confirm I'm the sole owner of the bitcoin address I provided and I will be sending my own funds to bittr. Order: \(ibanEntity.emailToken.prefix(32)). IBAN: \(ibanEntity.yourIbanNumber)"
        let signingPath = BitcoinManager.shared.defaultBip84SigningPath()
        let signature = try! BitcoinManager.shared.signMessageForPath(path: signingPath, message: message)
        
        Task {
            let lightningSignature:String
            do {
                lightningSignature = try await BitcoinManager.shared.signMessage(message: message)
            } catch {
                Log.info("310 Error: \(error.localizedDescription)")
                SentryManager.capture(error, context: "Transfer2ViewController row 313")
                return
            }
            
            // Check whether BDK wallet has loaded.
            var bdkAttempts = 0
            while BitcoinManager.shared.bdkWallet == nil {
                if bdkAttempts < 4 {
                    try? await Task.sleep(nanoseconds: 3 * NSEC_PER_SEC)
                    bdkAttempts += 1
                } else {
                    // There's a problem loading BDK.
                    self.showAlert(title: Language.getWord(withID: "oops"), message: Language.getWord(withID: "syncingwallet2"), buttons: [.dismiss(Language.getWord(withID: "okay"))])
                    return
                }
            }
            // Get real onchain address.
            let firstAddress = BitcoinManager.shared.getBittrAddress()
            Log.debug("Address: \(firstAddress)")
            
            // Get node ID.
            guard let lightningPubKey = BitcoinManager.shared.nodeId() else {
                Log.info("Wallet has not yet been synced. Pubkey is unavailable.")
                self.showAlert(title: Language.getWord(withID: "oops"), message: Language.getWord(withID: "syncingwallet2"), buttons: [.dismiss(Language.getWord(withID: "okay"))])
                return
            }
            
            // Get xpub.
            let xpub = BitcoinManager.shared.xpub
            
            // Gather parameters.
            var parameters: [String: Any] = [
                "email": ibanEntity.yourEmail,
                "email_token": ibanEntity.emailToken,
                "bitcoin_address": firstAddress,
                "initial_address_type": "extended",
                "category": "ios",
                "bitcoin_message": message,
                "bitcoin_signature": signature,
                "iban": ibanEntity.yourIbanNumber,
                "lightning_pubkey": lightningPubKey,
                "lightning_signature": lightningSignature,
                "xpub_key": xpub,
                "xpub_addr_type": "bech32",
                "xpub_path": "m/0/x",
                "skip_xpub_usage_check": "true",
                "ios_device_token": CacheManager.getRegistrationToken() ?? ""
            ]
            // Without push notifications the user can't receive instant lightning
            // payouts, so register them with on-chain payouts instead of lightning.
            if self.notificationsDenied {
                parameters["payment_mode"] = "onchain"
            }

            // Recovery: reuse the existing deposit code so the backend updates the
            // existing customer instead of creating a new order. lightning_pubkey
            // (above) must match the one sent in check2fa and stored on the customer.
            if let restoreDepositCode = restoreDepositCode {
                parameters["deposit_code"] = restoreDepositCode
            }

            // Send details to Bittr.
            self.createBittrAccount(ibanEntity: ibanEntity, parameters: parameters)
        }
    }
    
    
    func createBittrAccount(ibanEntity:IbanEntity, parameters:[String: Any]) {
        
        // Start animating.
        self.nextButtonActivityIndicator.startAnimating()
        self.nextButtonLabel.alpha = 0
        self.nextButtonArrow.alpha = 0
        
        // Make API call.
        Task {
            let envUrl = "\(EnvironmentConfig.bittrAPIBaseURL)/customer"
            await CallsManager.makeApiCall(url: envUrl, parameters: parameters, getOrPost: .post) { result in
                
                DispatchQueue.main.async {
                    // Stop spinner.
                    self.nextButtonActivityIndicator.stopAnimating()
                    self.nextButtonLabel.alpha = 1
                    self.nextButtonArrow.alpha = 1
                    self.codeTextField.text = nil
                    
                    switch result {
                    case .failure(let error):
                        self.showAlert(title: Language.getWord(withID: "oops"), message: Language.getWord(withID: "bittrsignupfail"), buttons: [.dismiss(Language.getWord(withID: "okay"))])
                        SentryManager.capture(error, context: "Transfer15ViewController258")
                    case .success(let receivedDictionary):
                        if let actualDataItems = receivedDictionary["data"] as? NSDictionary,
                            let dataOurIban = actualDataItems["iban"] as? String,
                            let dataCode = actualDataItems["deposit_code"] as? String,
                            let dataSwift = actualDataItems["swift"] as? String {
                            
                            // Signup successful.
                            let lightningAddressUsername = actualDataItems["lightning_address_username"] as? String ?? ""
                            
                            CacheManager.addBittrIban(ibanID: ibanEntity.id, ourIban: dataOurIban, ourSwift: dataSwift, yourCode: dataCode, lightningAddressUsername: lightningAddressUsername)

                            // If the user proceeded without notifications, the account was
                            // registered on-chain, so persist that locally too.
                            if self.notificationsDenied {
                                CacheManager.setPaymentMode(ibanID: ibanEntity.id, paymentMode: "onchain")
                            }
                            for (index, eachIbanEntity) in BitcoinManager.shared.bittrWallet.ibanEntities.enumerated() {
                                if eachIbanEntity.id == ibanEntity.id {
                                    BitcoinManager.shared.bittrWallet.ibanEntities[index].ourIbanNumber = dataOurIban
                                    BitcoinManager.shared.bittrWallet.ibanEntities[index].ourSwift = dataSwift
                                    BitcoinManager.shared.bittrWallet.ibanEntities[index].yourUniqueCode = dataCode
                                    BitcoinManager.shared.bittrWallet.ibanEntities[index].lightningAddressUsername = lightningAddressUsername
                                    if self.notificationsDenied {
                                        BitcoinManager.shared.bittrWallet.ibanEntities[index].paymentMode = "onchain"
                                    }

                                    self.coreVC!.buyVC?.parseIbanEntities(uponPageLaunch: false)
                                }
                            }
                            
                            // Move to next page.
                            self.signupVC?.moveToPage(12)
                            self.ibanVC?.moveToPage(3)
                        } else if let actualApiMessage = receivedDictionary["message"] as? String {
                            // Some message has been received.
                            if actualApiMessage == "Unable to create customer account (invalid iban)" {
                                self.showAlert(title: Language.getWord(withID: "oops"), message: Language.getWord(withID: "bittrsignupfail2"), buttons: [.action(Language.getWord(withID: "okay")) { self.backToPreviousPage() }])
                            } else {
                                self.showAlert(title: Language.getWord(withID: "oops"), message: "\(Language.getWord(withID: "bittrsignupfail3")) (\(actualApiMessage).)", buttons: [.action(Language.getWord(withID: "okay")) { self.backToPreviousPage() }])
                            }
                        }
                    }
                }
            }
        }
    }
    
    func backToPreviousPage() {
        self.signupVC?.moveToPage(10)
        self.ibanVC?.moveToPage(1)
    }
    
    
    @IBAction func resendCodeButtonTapped(_ sender: UIButton) {
        // User can request a new email verification code every 30 seconds.
        
        if self.counter == 0 {
            // 30 seconds have passed since previous request.
            let currentIbanID = self.signupVC?.currentIbanID ?? self.ibanVC!.currentIbanID
            for eachIbanEntity in BitcoinManager.shared.bittrWallet.ibanEntities {
                if eachIbanEntity.id == currentIbanID {
                    Task {
                        await self.didSendDetailsToBittr(email: eachIbanEntity.yourEmail, iban: eachIbanEntity.yourIbanNumber) { didSendDetails in
                            
                            DispatchQueue.main.async {
                                if didSendDetails {
                                    // Success - show resend confirmation
                                    self.showAlert(title: Language.getWord(withID: "emailresent"), message: "\(Language.getWord(withID: "emailresent2")) \(eachIbanEntity.yourEmail).", buttons: [.dismiss(Language.getWord(withID: "okay")), .action(Language.getWord(withID: "changeemail")) { self.backToChangeEmail() }])
                                    
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
            self.showAlert(title: "", message: Language.getWord(withID: "resendcode2"), buttons: [.dismiss(Language.getWord(withID: "okay")), .action(Language.getWord(withID: "changeemail")) { self.backToChangeEmail() }])
        }
    }
    
    func backToChangeEmail() {
        self.signupVC?.moveToPage(10)
        self.ibanVC?.moveToPage(1)
    }
    
    
    @objc func updateCounter() {
        if counter > 0 {
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
            } else if trimmedText.count < 6 {
                // Re-arm auto-submit once the code drops below 6 digits, so a
                // corrected code (e.g. after a wrong-code error) auto-triggers
                // again on its 6th keystroke.
                self.hasAutoTriggered = false
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
    
    func changeColors() {
        
        self.topLabel.textColor = Colors.getColor("blackorwhite")
        self.centerCard.backgroundColor = Colors.getColor("yelloworblue1")
        
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
