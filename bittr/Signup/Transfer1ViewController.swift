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
    
    override func viewDidLoad() {
        super.viewDidLoad()

        // Corner radii and button titles.
        ibanView.layer.cornerRadius = 13
        emailView.layer.cornerRadius = 13
        nextView.layer.cornerRadius = 13
        cardView.layer.cornerRadius = 13
        imageContainer.layer.cornerRadius = 13
        ibanButton.setTitle("", for: .normal)
        emailButton.setTitle("", for: .normal)
        nextButton.setTitle("", for: .normal)
        backgroundButton.setTitle("", for: .normal)
        backgroundButton2.setTitle("", for: .normal)
        skipButton.setTitle("", for: .normal)
        articleButton.setTitle("", for: .normal)
        
        // Text fields.
        ibanTextField.delegate = self
        emailTextField.delegate = self
        
        // Notification observers.
        NotificationCenter.default.addObserver(self, selector: #selector(setSignupArticles), name: NSNotification.Name(rawValue: "setsignuparticles"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(setArticleImage), name: NSNotification.Name(rawValue: "setimage\(pageArticle1Slug)"), object: nil)
        
        if let actualArticles = articles {
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
        }
        
        if let actualImages = allImages {
            if let actualImage = actualImages[pageArticle1Slug] {
                self.articleImage.image = actualImage
            }
        }
        
        self.changeColors()
    }
    
    @objc func setSignupArticles(notification:NSNotification) {
        
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
            let parameters = [
              [
                "key": "email",
                "value": self.emailTextField.text!,
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
                        let alert = UIAlertController(title: "Oops!", message: "Something went wrong verifying your email address. Please try again.", preferredStyle: .alert)
                        alert.addAction(UIAlertAction(title: Language.getWord(withID: "okay"), style: .cancel, handler: nil))
                        self.present(alert, animated: true)
                        if let actualError = error {
                            SentrySDK.capture(error: actualError)
                        }
                    }
                    return
                }
                // Response received from Bittr API.
                
                DispatchQueue.main.async {
                    // Send details to next signup page.
                    let notificationDict:[String: Any] = ["page":sender.accessibilityIdentifier, "client":self.currentClientID, "iban":self.currentIbanID]
                    // Move to next page.
                    NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "signupnext"), object: nil, userInfo: notificationDict) as Notification)
                    self.nextButtonActivityIndicator.stopAnimating()
                    self.nextButtonLabel.alpha = 1
                }
            }
            task.resume()
            
        }
    }
    
    @IBAction func skipButtonTapped(_ sender: UIButton) {
        
        // User indicates they don't have an IBAN.
        self.view.endEditing(true)
        
        let alert = UIAlertController(title: "We're sorry!", message: "Buying bitcoin with bittr is only available to IBAN holders.\n\nYou can still use your wallet to send and receive bitcoin from other sellers.", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Go to wallet", style: .cancel, handler: {_ in
            NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "restorewallet"), object: nil, userInfo: nil) as Notification)
        }))
        alert.addAction(UIAlertAction(title: "Cancel", style: .default, handler: nil))
        self.present(alert, animated: true)
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
    
    func isValidEmail(_ email: String) -> Bool {
        let emailRegEx = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"

        let emailPred = NSPredicate(format:"SELF MATCHES %@", emailRegEx)
        return emailPred.evaluate(with: email)
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
        
        self.topLabelOne.textColor = Colors.getColor(color: "black")
        self.topLabelTwo.textColor = Colors.getColor(color: "black")
        self.topLabelThree.textColor = Colors.getColor(color: "black")
        
        if CacheManager.darkModeIsOn() {
            self.ibanLabel.textColor = Colors.getColor(color: "black")
        } else {
            self.ibanLabel.textColor = Colors.getColor(color: "transparentblack")
        }
    }
    
}
