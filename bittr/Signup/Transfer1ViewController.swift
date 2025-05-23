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
    
    @IBOutlet weak var scrollView: UIScrollView!
    @IBOutlet weak var contentView: UIView!
    @IBOutlet weak var contentViewBottom: NSLayoutConstraint!
    
    @IBOutlet weak var backgroundButton: UIButton!
    @IBOutlet weak var backgroundButton2: UIButton!
    
    @IBOutlet weak var nextButtonLabel: UILabel!
    @IBOutlet weak var nextButtonActivityIndicator: UIActivityIndicatorView!
    
    var currentClientID = ""
    var currentIbanID = ""
    
    @IBOutlet weak var spinner1: UIActivityIndicatorView!
    @IBOutlet weak var articleImage: UIImageView!
    @IBOutlet weak var articleTitle: UILabel!
    let pageArticle1Slug = "supported-countries"
    var pageArticle1 = Article()
    
    var articles:[String:Article]?
    var allImages:[String:UIImage]?
    var coreVC:CoreViewController?
    var signupVC:SignupViewController?
    
    override func viewDidLoad() {
        super.viewDidLoad()

        // Corner radii
        self.ibanView.layer.cornerRadius = 13
        self.emailView.layer.cornerRadius = 13
        self.nextView.layer.cornerRadius = 13
        self.cardView.layer.cornerRadius = 13
        self.imageContainer.layer.cornerRadius = 13
        
        // Button titles
        self.ibanButton.setTitle("", for: .normal)
        self.emailButton.setTitle("", for: .normal)
        self.nextButton.setTitle("", for: .normal)
        self.backgroundButton.setTitle("", for: .normal)
        self.backgroundButton2.setTitle("", for: .normal)
        self.skipButton.setTitle("", for: .normal)
        self.articleButton.setTitle("", for: .normal)
        
        // Text fields.
        self.ibanTextField.delegate = self
        self.emailTextField.delegate = self
        
        // Notification observers.
        //NotificationCenter.default.addObserver(self, selector: #selector(setSignupArticles), name: NSNotification.Name(rawValue: "setsignuparticles"), object: nil)
        //NotificationCenter.default.addObserver(self, selector: #selector(setArticleImage), name: NSNotification.Name(rawValue: "setimage\(pageArticle1Slug)"), object: nil)
        
        /*if let actualArticles = articles {
            if let actualArticle = actualArticles[pageArticle1Slug] {
                self.pageArticle1 = actualArticle
                DispatchQueue.main.async {
                    self.articleTitle.text = self.pageArticle1.title
                    if let actualData = CacheManager.getImage(key: self.pageArticle1.image) {
                        self.articleImage.image = UIImage(data: actualData)
                    }
                    if self.articleImage.image != nil {
                        self.spinner1.stopAnimating()
                    }
                }
                self.articleButton.accessibilityIdentifier = self.pageArticle1Slug
            }
        }*/
        
        /*if let actualImages = allImages {
            if let actualImage = actualImages[pageArticle1Slug] {
                self.articleImage.image = actualImage
            }
        }*/
        
        self.changeColors()
        self.setWords()
        self.getSignupArticle()
    }
    
    func getSignupArticle() {
        
        Task {
            await self.getArticle(self.pageArticle1Slug, coreVC: self.signupVC!.coreVC!) { result in
                
                switch result {
                case .success(let receivedArticle):
                    self.pageArticle1 = receivedArticle
                    DispatchQueue.main.async {
                        self.articleTitle.text = self.pageArticle1.title
                        if let actualData = CacheManager.getImage(key: self.pageArticle1.image) {
                            self.articleImage.image = UIImage(data: actualData)
                        }
                        if self.articleImage.image != nil {
                            self.spinner1.stopAnimating()
                        }
                    }
                    self.articleButton.accessibilityIdentifier = self.pageArticle1Slug
                case .failure(let receivedError):
                    print("Couldn't get article: \(receivedError)")
                }
            }
        }
    }
    
    /*@objc func setSignupArticles(notification:NSNotification) {
        
        if let userInfo = notification.userInfo as [AnyHashable:Any]? {
            if let actualArticle = userInfo[pageArticle1Slug] as? Article {
                self.pageArticle1 = actualArticle
                DispatchQueue.main.async {
                    self.articleTitle.text = self.pageArticle1.title
                }
                self.articleButton.accessibilityIdentifier = self.pageArticle1Slug
            }
        }
    }
    
    @objc func setArticleImage(notification:NSNotification) {
        
        if let userInfo = notification.userInfo as [AnyHashable:Any]? {
            if let actualImage = userInfo["image"] as? UIImage {
                self.spinner1.stopAnimating()
                self.articleImage.image = actualImage
            }
        }
    }*/
    
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
            
            self.nextButtonLabel.alpha = 0
            self.nextButtonActivityIndicator.startAnimating()
            
            var envKey = "proddevice"
            if UserDefaults.standard.value(forKey: "envkey") as? Int == 0 {
                envKey = "device"
            }
            
            // Store new client details in cache.
            let deviceDict = UserDefaults.standard.value(forKey: envKey) as? NSDictionary
            if let actualDeviceDict = deviceDict {
                // Client exists in cache.
                let clients:[Client] = CacheManager.parseDevice(deviceDict: actualDeviceDict)
                
                if self.currentClientID != "", self.currentIbanID != "" {
                    // We're updating information to an existing IBAN entity.
                    for client in clients {
                        if client.id == self.currentClientID {
                            for iban in client.ibanEntities {
                                if iban.id == self.currentIbanID {
                                    iban.yourEmail = self.emailTextField.text!.trimmingCharacters(in: .whitespacesAndNewlines)
                                    iban.yourIbanNumber = self.ibanTextField.text!.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: " ", with: "")
                                    
                                    CacheManager.addIban(clientID: self.currentClientID, iban: iban)
                                }
                            }
                        }
                    }
                } else if self.currentClientID != "", self.currentIbanID == "" {
                    // We're adding another IBAN to an existing client.
                    for client in clients {
                        if client.id == self.currentClientID {
                            let newIbanEntity = IbanEntity()
                            newIbanEntity.order = client.ibanEntities.count
                            newIbanEntity.id = UUID().uuidString
                            newIbanEntity.yourEmail = self.emailTextField.text!.trimmingCharacters(in: .whitespacesAndNewlines)
                            newIbanEntity.yourIbanNumber = self.ibanTextField.text!.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: " ", with: "")
                            client.ibanEntities += [newIbanEntity]
                            CacheManager.addIban(clientID: client.id, iban: newIbanEntity)
                            
                            self.currentIbanID = newIbanEntity.id
                        }
                    }
                } else if self.currentClientID == "", clients.count == 1 {
                    self.currentClientID = clients[0].id
                    self.currentIbanID = clients[0].ibanEntities[0].id
                    clients[0].ibanEntities[0].yourIbanNumber = self.ibanTextField.text!.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: " ", with: "")
                    clients[0].ibanEntities[0].yourEmail = self.emailTextField.text!.trimmingCharacters(in: .whitespacesAndNewlines)
                    CacheManager.addIban(clientID: self.currentClientID, iban: clients[0].ibanEntities[0])
                }
            } else {
                // No clients exist yet in cache.
                let newClient = Client()
                newClient.order = 0
                newClient.id = UUID().uuidString
                let newIbanEntity = IbanEntity()
                newIbanEntity.order = 0
                newIbanEntity.id = UUID().uuidString
                newIbanEntity.yourEmail = self.emailTextField.text!.trimmingCharacters(in: .whitespacesAndNewlines)
                newIbanEntity.yourIbanNumber = self.ibanTextField.text!.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: " ", with: "")
                newClient.ibanEntities += [newIbanEntity]
                CacheManager.addIban(clientID: newClient.id, iban: newIbanEntity)
                
                self.currentClientID = newClient.id
                self.currentIbanID = newIbanEntity.id
            }
            
            // Send email to bittr API for email verification. Bittr will send email.
            let parameters: [String: Any] = [
                "email": self.emailTextField.text!,
                "category": "ios"
            ]
            
            // TODO: Public?
            var envUrl = "https://getbittr.com/api/verify/email"
            if UserDefaults.standard.value(forKey: "envkey") as? Int == 0 {
                envUrl = "https://model-arachnid-viable.ngrok-free.app/verify/email"
            }
            
            Task {
                await CallsManager.makeApiCall(url: envUrl, parameters: parameters, getOrPost: "POST") { result in
                    
                    switch result {
                    case .success(let receivedDictionary):
                        DispatchQueue.main.async {
                            // Send details to next signup page.
                            let notificationDict:[String: Any] = ["page":sender.accessibilityIdentifier!, "client":self.currentClientID, "iban":self.currentIbanID]
                            
                            // Move to next page.
                            self.signupVC?.moveToPage(11)
                            
                            /*NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "signupnext"), object: nil, userInfo: notificationDict) as Notification)*/
                            self.nextButtonActivityIndicator.stopAnimating()
                            self.nextButtonLabel.alpha = 1
                        }
                    case .failure(let error):
                        DispatchQueue.main.async {
                            self.showAlert(presentingController: self, title: Language.getWord(withID: "oops"), message: Language.getWord(withID: "bittrsignupfail4"), buttons: [Language.getWord(withID: "okay")], actions: nil)
                            SentrySDK.capture(error: error)
                        }
                    }
                    
                }
            }
        }
    }
    
    @IBAction func skipButtonTapped(_ sender: UIButton) {
        
        // User indicates they don't have an IBAN.
        self.view.endEditing(true)
        self.showAlert(presentingController: self, title: Language.getWord(withID: "weresorry"), message: Language.getWord(withID: "onlyiban"), buttons: [Language.getWord(withID: "gotowallet"), Language.getWord(withID: "cancel")], actions: [#selector(self.alertGoToWallet), nil])
    }
    
    @objc func alertGoToWallet() {
        self.hideAlert()
        NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "restorewallet"), object: nil, userInfo: nil) as Notification)
        self.coreVC?.setClient()
    }
    
    @IBAction func backgroundButtonTapped(_ sender: UIButton) {
        self.view.endEditing(true)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillDisappear), name: UIResponder.keyboardWillHideNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillAppear), name: UIResponder.keyboardWillShowNotification, object: nil)
    }
    
    @objc func keyboardWillDisappear() {
        
        updateButtonColor()
        
        self.ibanButton.alpha = 1
        self.emailButton.alpha = 1
        
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
        
        if let nextField = textField.superview?.superview?.viewWithTag(textField.tag + 1) as? UITextField {
            nextField.becomeFirstResponder()
        } else {
            textField.resignFirstResponder()
        }
        
        return false
    }
    
    func updateButtonColor() {
        
        if self.ibanTextField.text?.trimmingCharacters(in: .whitespacesAndNewlines) != "" && self.isValidEmail(self.emailTextField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "") {
            
            self.nextView.backgroundColor = UIColor.black
        } else {
            self.nextView.backgroundColor = UIColor(red: 0, green: 0, blue: 0, alpha: 0.6)
        }
    }
    
    func textFieldDidEndEditing(_ textField: UITextField) {
        updateButtonColor()
    }
    
    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        updateButtonColor()
        return true
    }
    
    @IBAction func articleButtonTapped(_ sender: UIButton) {
        
        let notificationDict:[String: Any] = ["tag":sender.accessibilityIdentifier]
        
        NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "launcharticle"), object: nil, userInfo: notificationDict) as Notification)
    }
    
    func changeColors() {
        
        self.topLabelOne.textColor = Colors.getColor("blackorwhite")
        self.topLabelTwo.textColor = Colors.getColor("blackorwhite")
        self.topLabelThree.textColor = Colors.getColor("blackorwhite")
        
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
    
    func isValidEmail(_ email: String) -> Bool {
        let emailRegEx = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"

        let emailPred = NSPredicate(format:"SELF MATCHES %@", emailRegEx)
        return emailPred.evaluate(with: email)
    }
}
