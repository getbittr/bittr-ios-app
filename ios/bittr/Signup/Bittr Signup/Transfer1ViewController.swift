//
//  Transfer1ViewController.swift
//  bittr
//
//  Created by Tom Melters on 09/06/2023.
//

import UIKit
import Sentry

class Transfer1ViewController: UIViewController, UITextFieldDelegate {

    // Enter iban and email for bittr signup.
    
    // Labels
    @IBOutlet weak var topLabelOne: UILabel!
    @IBOutlet weak var topLabelTwo: UILabel!
    @IBOutlet weak var topLabelThree: UILabel!
    
    // IBAN
    @IBOutlet weak var ibanView: UIView!
    @IBOutlet weak var ibanTextField: UITextField!
    @IBOutlet weak var ibanButton: UIButton!
    
    // Email
    @IBOutlet weak var emailView: UIView!
    @IBOutlet weak var emailTextField: UITextField!
    @IBOutlet weak var emailButton: UIButton!
    
    // Next
    @IBOutlet weak var nextView: UIView!
    @IBOutlet weak var nextButton: UIButton!
    @IBOutlet weak var cardView: UIView!
    @IBOutlet weak var imageContainer: UIView!
    @IBOutlet weak var skipButton: UIButton!
    @IBOutlet weak var ibanLabel: UILabel!
    @IBOutlet weak var articleButton: UIButton!
    
    // View items
    @IBOutlet weak var centerCard: UIView!
    @IBOutlet weak var scrollView: UIScrollView!
    @IBOutlet weak var contentView: UIView!
    @IBOutlet weak var contentViewBottom: NSLayoutConstraint!
    
    // Background buttons
    @IBOutlet weak var backgroundButton: UIButton!
    @IBOutlet weak var backgroundButton2: UIButton!
    @IBOutlet weak var backgroundButton3: UIButton!
    
    // Next button
    @IBOutlet weak var nextButtonLabel: UILabel!
    @IBOutlet weak var nextButtonArrow: UIImageView!
    @IBOutlet weak var nextButtonActivityIndicator: UIActivityIndicatorView!
    
    // Article
    @IBOutlet weak var spinner1: UIActivityIndicatorView!
    @IBOutlet weak var articleImage: UIImageView!
    @IBOutlet weak var articleTitle: UILabel!
    let pageArticle1Slug = "supported-countries"
    var pageArticle1 = Article()
    
    // Variables
    var coreVC:CoreViewController?
    var signupVC:SignupViewController?
    var ibanVC:RegisterIbanViewController?
    
    override func viewDidLoad() {
        super.viewDidLoad()

        // Corner radii
        self.ibanView.layer.cornerRadius = 8
        self.emailView.layer.cornerRadius = 8
        self.nextView.layer.cornerRadius = 8
        self.cardView.layer.cornerRadius = 8
        self.imageContainer.layer.cornerRadius = 8
        self.centerCard.layer.cornerRadius = 13
        self.centerCard.setShadow()
        self.cardView.setShadow()
        
        // Button titles
        self.ibanButton.setTitle("", for: .normal)
        self.emailButton.setTitle("", for: .normal)
        self.nextButton.setTitle("", for: .normal)
        self.backgroundButton.setTitle("", for: .normal)
        self.backgroundButton2.setTitle("", for: .normal)
        self.backgroundButton3.setTitle("", for: .normal)
        self.skipButton.setTitle("", for: .normal)
        self.articleButton.setTitle("", for: .normal)
        
        // Text fields.
        self.ibanTextField.delegate = self
        self.emailTextField.delegate = self
        
        self.topLabelOne.accessibilityIdentifier = TestID.Signup.Bittr.Start.topLabelOne
        self.topLabelTwo.accessibilityIdentifier = TestID.Signup.Bittr.Start.topLabelTwo
        self.topLabelThree.accessibilityIdentifier = TestID.Signup.Bittr.Start.topLabelThree
        self.ibanTextField.accessibilityIdentifier = TestID.Signup.Bittr.Start.ibanTextField
        self.ibanButton.accessibilityIdentifier = TestID.Signup.Bittr.Start.ibanButton
        self.emailTextField.accessibilityIdentifier = TestID.Signup.Bittr.Start.emailTextField
        self.emailButton.accessibilityIdentifier = TestID.Signup.Bittr.Start.emailButton
        self.nextButton.accessibilityIdentifier = TestID.Signup.Bittr.Start.nextButton
        self.skipButton.accessibilityIdentifier = TestID.Signup.Bittr.Start.skipButton

        // Set colors, language, article.
        self.changeColors()
        self.setWords()
        Task {
            await self.setSignupArticle(articleSlug: self.pageArticle1Slug, coreVC: self.signupVC?.coreVC ?? self.coreVC!, articleButton: self.articleButton, articleTitle: self.articleTitle, articleImage: self.articleImage, articleSpinner: self.spinner1, completion: { article in
                self.pageArticle1 = article ?? Article()
            })
        }
    }
    
    override func viewDidAppear(_ animated: Bool) {
        self.triggerIbanAutoFocus()
    }
    
    func triggerIbanAutoFocus() {
        // Auto-focus on IBAN field when triggered from previous page
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.ibanTextField.becomeFirstResponder()
            self.ibanButton.alpha = 0
        }
    }
    
    @IBAction func ibanButtonTapped(_ sender: UIButton) {
        
        // Launch IBAN text field.
        self.ibanTextField.becomeFirstResponder()
        self.ibanButton.alpha = 0
    }
    
    @IBAction func emailButtonTapped(_ sender: UIButton) {
        
        // Launch email text field.
        self.emailTextField.becomeFirstResponder()
        self.emailButton.alpha = 0
    }
    
    @IBAction func nextButtonTapped(_ sender: UIButton) {
        
        self.view.endEditing(true)
        self.updateButtonColor()
        
        if self.nextView.backgroundColor == UIColor.black {
            // Fields have been filled.
            self.nextButtonLabel.alpha = 0
            self.nextButtonArrow.alpha = 0
            self.nextButtonActivityIndicator.startAnimating()
            self.gatherIbanDetails()
        } else {
            // Fields have not yet been filled.
            self.showAlert(presentingController: self.signupVC?.coreVC ?? self.signupVC ?? self.ibanVC ?? self, title: Language.getWord(withID: "oops"), message: Language.getWord(withID: "transfer1vc"), buttons: [Language.getWord(withID: "okay")], actions: nil)
        }
    }
    
    func gatherIbanDetails() {
        
        let currentIbanID = self.signupVC?.currentIbanID ?? self.ibanVC!.currentIbanID
        let enteredEmail = self.emailTextField.text!.trimmingCharacters(in: .whitespacesAndNewlines)
        let enteredIban = self.ibanTextField.text!.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: " ", with: "")
        
        if currentIbanID != "" {
            // We're updating information to an existing IBAN entity.
            for (index, eachIbanEntity) in self.coreVC!.bittrWallet.ibanEntities.enumerated() {
                if eachIbanEntity.id == currentIbanID {
                    eachIbanEntity.yourEmail = enteredEmail
                    eachIbanEntity.yourIbanNumber = enteredIban
                    self.coreVC!.bittrWallet.ibanEntities[index] = eachIbanEntity
                    CacheManager.addIban(iban: eachIbanEntity)
                }
            }
        } else {
            // We're adding a new IBAN entity.
            let newIbanEntity = IbanEntity()
            newIbanEntity.order = self.coreVC!.bittrWallet.ibanEntities.count
            newIbanEntity.id = UUID().uuidString
            newIbanEntity.yourEmail = enteredEmail
            newIbanEntity.yourIbanNumber = enteredIban
            
            self.coreVC!.bittrWallet.ibanEntities += [newIbanEntity]
            CacheManager.addIban(iban: newIbanEntity)
            self.signupVC?.currentIbanID = newIbanEntity.id
            self.ibanVC?.currentIbanID = newIbanEntity.id
        }
        
        self.sendDetailsToBittr(enteredEmail: enteredEmail, enteredIban: enteredIban)
    }
    
    func sendDetailsToBittr(enteredEmail:String, enteredIban:String) {
        
        Task {
            await self.didSendDetailsToBittr(email: enteredEmail, iban: enteredIban) { didSendDetails in
                DispatchQueue.main.async {
                    self.nextButtonActivityIndicator.stopAnimating()
                    self.nextButtonLabel.alpha = 1
                    self.nextButtonArrow.alpha = 1
                    
                    if didSendDetails {
                        // Success - move to next page
                        self.signupVC?.moveToPage(11)
                        self.ibanVC?.moveToPage(2)
                    }
                }
            }
        }
    }
    
    @IBAction func skipButtonTapped(_ sender: UIButton) {
        
        // User indicates they don't have an IBAN.
        self.view.endEditing(true)
        self.showAlert(presentingController: self.signupVC?.coreVC ?? self.signupVC ?? self.ibanVC ?? self, title: Language.getWord(withID: "weresorry"), message: Language.getWord(withID: "onlyiban"), buttons: [Language.getWord(withID: "gotowallet"), Language.getWord(withID: "cancel")], actions: [#selector(self.alertGoToWallet), nil])
    }
    
    @objc func alertGoToWallet() {
        self.hideAlert()
        self.coreVC!.buyVC?.registerIbanVC?.dismiss(animated: true)
        self.coreVC!.buyVC?.parseIbanEntities(uponPageLaunch: false)
        self.coreVC!.hideSignup()
    }
    
    @IBAction func backgroundButtonTapped(_ sender: UIButton) {
        self.view.endEditing(true)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillDisappear), name: UIResponder.keyboardWillHideNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillAppear), name: UIResponder.keyboardWillShowNotification, object: nil)
    }
    
    @objc func keyboardWillDisappear() {
        
        self.updateButtonColor()
        
        self.ibanButton.alpha = 1
        self.emailButton.alpha = 1
        
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
        
        // If email field is active and verify button is enabled, trigger verification
        if textField == self.emailTextField && self.nextView.backgroundColor == UIColor.black {
            self.nextButtonTapped(UIButton())
            return true
        }
        
        if let nextField = textField.superview?.superview?.viewWithTag(textField.tag + 1) as? UITextField {
            nextField.becomeFirstResponder()
        } else {
            textField.resignFirstResponder()
        }
        
        return false
    }
    
    func updateButtonColor() {
        
        if self.ibanTextField.text?.trimmingCharacters(in: .whitespacesAndNewlines) != "" && (self.emailTextField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "").isValidEmail() {
            
            self.nextView.backgroundColor = UIColor.black
        } else {
            self.nextView.backgroundColor = UIColor(red: 0, green: 0, blue: 0, alpha: 0.6)
        }
    }
    
    func textFieldDidEndEditing(_ textField: UITextField) {
        self.updateButtonColor()
    }
    
    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        self.updateButtonColor()
        return true
    }
    
    @IBAction func articleButtonTapped(_ sender: UIButton) {
        if let slug = sender.boundString {
            self.coreVC!.launchArticle(articleTag: slug)
        }
    }
    
    func changeColors() {
        
        self.topLabelOne.textColor = Colors.getColor("blackorwhite")
        self.topLabelTwo.textColor = Colors.getColor("blackorwhite")
        self.topLabelThree.textColor = Colors.getColor("blackorwhite")
        self.centerCard.backgroundColor = Colors.getColor("yelloworblue1")
        
        if CacheManager.darkModeIsOn() {
            self.ibanLabel.textColor = Colors.getColor("blackorwhite")
        } else {
            self.ibanLabel.textColor = Colors.getColor("transparentblack")
        }
    }
    
    func setWords() {
        
        self.topLabelOne.text = Language.getWord(withID: "bittrinstructions4")
        self.topLabelTwo.text = Language.getWord(withID: "whatsyouriban")
        self.topLabelThree.text = Language.getWord(withID: "whatsyouremail")
        self.ibanTextField.placeholder = Language.getWord(withID: "enteriban")
        self.emailTextField.placeholder = Language.getWord(withID: "enteremail")
        self.nextButtonLabel.text = Language.getWord(withID: "verify")
        self.ibanLabel.text = Language.getWord(withID: "noiban")
    }
    
}

extension UIViewController {
    
    func didSendDetailsToBittr(email:String, iban:String, completion: @escaping (Bool) -> Void) async {
        
        // Send email and IBAN to bittr API for verification. Bittr will send email and validate IBAN.
        let parameters: [String: Any] = [
            "email": email,
            "iban": iban,
            "category": "ios"
        ]
        
        // Make API call.
        let envUrl = "\(EnvironmentConfig.bittrAPIBaseURL)/verify/email"
        await CallsManager.makeApiCall(url: envUrl, parameters: parameters, getOrPost: .post) { result in
            
            let presentingController = (self as? Transfer1ViewController)?.signupVC?.coreVC ?? (self as? Transfer1ViewController)?.ibanVC ?? (self as? Transfer2ViewController)?.signupVC?.coreVC ?? (self as? Transfer2ViewController)?.ibanVC ?? self
            
            switch result {
            case .success(let json):
                    // Check if the response contains an error message
                    if let success = json["success"] as? Bool,
                       success == false,
                       let message = json["message"] as? String {
                        
                        // IBAN validation failed
                        self.showAlert(presentingController: presentingController, title: Language.getWord(withID: "oops"), message: message, buttons: [Language.getWord(withID: "okay")], actions: nil)
                        completion(false)
                    } else {
                        completion(true)
                    }
            case .failure(let error):
                self.showAlert(presentingController: presentingController, title: Language.getWord(withID: "oops"), message: Language.getWord(withID: "bittrsignupfail4"), buttons: [Language.getWord(withID: "okay")], actions: nil)
                SentrySDK.capture(error: error) { scope in
                    scope.setExtra(value: "Transfer1ViewController row 194", key: "context")
                }
                completion(false)
            }
        }
    }
}
