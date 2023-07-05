//
//  Transfer1ViewController.swift
//  bittr
//
//  Created by Tom Melters on 09/06/2023.
//

import UIKit

class Transfer1ViewController: UIViewController, UITextFieldDelegate {

    @IBOutlet weak var ibanView: UIView!
    @IBOutlet weak var ibanTextField: UITextField!
    @IBOutlet weak var ibanButton: UIButton!
    @IBOutlet weak var emailView: UIView!
    @IBOutlet weak var emailTextField: UITextField!
    @IBOutlet weak var emailButton: UIButton!
    @IBOutlet weak var nextView: UIView!
    @IBOutlet weak var nextButton: UIButton!
    @IBOutlet weak var cardView: UIView!
    @IBOutlet weak var imageContainer: UIView!
    @IBOutlet weak var skipButton: UIButton!
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
    
    override func viewDidLoad() {
        super.viewDidLoad()

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
        
        ibanTextField.delegate = self
        emailTextField.delegate = self
    }
    
    @IBAction func ibanButtonTapped(_ sender: UIButton) {
        
        self.ibanTextField.becomeFirstResponder()
        self.ibanButton.alpha = 0
    }
    
    @IBAction func emailButtonTapped(_ sender: UIButton) {
        
        self.emailTextField.becomeFirstResponder()
        self.emailButton.alpha = 0
    }
    
    @IBAction func nextButtonTapped(_ sender: UIButton) {
        
        self.view.endEditing(true)
        self.updateButtonColor()
        
        if self.nextView.backgroundColor == UIColor.black {
            
            self.nextButtonLabel.alpha = 0
            self.nextButtonActivityIndicator.startAnimating()
            
            let deviceDict = UserDefaults.standard.value(forKey: "device") as? NSDictionary
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
                    } /*else {
                        let paramSrc = param["src"] as! String
                        let fileData = try NSData(contentsOfFile:paramSrc, options:[]) as Data
                        let fileContent = String(data: fileData, encoding: .utf8)!
                        body += "; filename=\"\(paramSrc)\"\r\n"
                                + "Content-Type: \"content-type header\"\r\n\r\n\(fileContent)\r\n"
                    }*/
                }
            }
            body += "--\(boundary)--\r\n";
            let postData = body.data(using: .utf8)
            var request = URLRequest(url: URL(string: "https://staging.getbittr.com/api/verify/email")!,timeoutInterval: Double.infinity)
            request.addValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            request.httpMethod = "POST"
            request.httpBody = postData
            let task = URLSession.shared.dataTask(with: request) { data, response, error in
                guard let data = data else {
                    print(String(describing: error))
                    DispatchQueue.main.async {
                        let alert = UIAlertController(title: "Oops!", message: "Something went wrong verifying your email address. Please try again.", preferredStyle: .alert)
                        alert.addAction(UIAlertAction(title: "Okay", style: .cancel, handler: nil))
                        self.present(alert, animated: true)
                    }
                    return
                }
                print(String(data: data, encoding: .utf8)!)
                
                DispatchQueue.main.async {
                    let notificationDict:[String: Any] = ["page":sender.accessibilityIdentifier, "client":self.currentClientID, "iban":self.currentIbanID]
                     NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "signupnext"), object: nil, userInfo: notificationDict) as Notification)
                    self.nextButtonActivityIndicator.stopAnimating()
                    self.nextButtonLabel.alpha = 1
                }
            }
            task.resume()
            
        }
    }
    
    @IBAction func skipButtonTapped(_ sender: UIButton) {
        
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
        
        let notificationDict:[String: Any] = ["tag":sender.tag]
        
        NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "launcharticle"), object: nil, userInfo: notificationDict) as Notification)
    }
}
