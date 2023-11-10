//
//  Transfer15ViewController.swift
//  bittr
//
//  Created by Tom Melters on 15/06/2023.
//

import UIKit
import BitcoinDevKit

class Transfer15ViewController: UIViewController, UITextFieldDelegate {
    
    @IBOutlet weak var codeView: UIView!
    @IBOutlet weak var nextView: UIView!
    @IBOutlet weak var codeTextField: UITextField!
    @IBOutlet weak var codeButton: UIButton!
    @IBOutlet weak var nextButton: UIButton!
    @IBOutlet weak var resendButton: UIButton!
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
    
    var addressViewModel = AddressViewModel()
    var nodeIDViewModel = NodeIDViewModel()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        codeView.layer.cornerRadius = 13
        nextView.layer.cornerRadius = 13
        
        codeTextField.delegate = self
        codeTextField.addDoneButton(target: self, returnaction: #selector(self.doneButtonTapped))
        
        codeButton.setTitle("", for: .normal)
        nextButton.setTitle("", for: .normal)
        resendButton.setTitle("", for: .normal)
        backgroundButton.setTitle("", for: .normal)
        backgroundButton2.setTitle("", for: .normal)
        
        NotificationCenter.default.addObserver(self, selector: #selector(updateClient), name: NSNotification.Name(rawValue: "signupnext"), object: nil)
    }
    
    @objc func updateClient(notification:NSNotification) {
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
        
        updateButtonColor()
        if self.nextView.backgroundColor == UIColor.black {
            
            self.nextButtonLabel.alpha = 0
            self.nextButtonActivityIndicator.startAnimating()
            
            let deviceDict = UserDefaults.standard.value(forKey: "device") as? NSDictionary
            if let actualDeviceDict = deviceDict {
                // Some device information exists.
                let clients:[Client] = CacheManager.parseDevice(deviceDict: actualDeviceDict)
                
                for client in clients {
                    if client.id == self.currentClientID {
                        
                        for iban in client.ibanEntities {
                            if iban.id == self.currentIbanID {
                                
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
                                
                                var request = URLRequest(url: URL(string: "https://staging.getbittr.com/api/verify/email/check2fa")!,timeoutInterval: Double.infinity)
                                request.addValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
                                request.httpMethod = "POST"
                                request.httpBody = postData
                                
                                let task = URLSession.shared.dataTask(with: request) { data, response, error in
                                    guard let data = data else {
                                        print(String(describing: error))
                                        return
                                    }
                                    print(String(data: data, encoding: .utf8)!)
                                    
                                    var dataDictionary:NSDictionary?
                                    if let receivedData = String(data: data, encoding: .utf8)?.data(using: String.Encoding.utf8) {
                                        
                                        do {
                                            dataDictionary = try JSONSerialization.jsonObject(with: receivedData, options: []) as? NSDictionary
                                            if let actualDataDict = dataDictionary {
                                                let emailToken = actualDataDict["token"]
                                                let errorMessage = actualDataDict["message"]
                                                if let actualEmailToken = emailToken as? String {
                                                    CacheManager.addEmailToken(clientID: self.currentClientID, ibanID: self.currentIbanID, emailToken: actualEmailToken)
                                                    
                                                    DispatchQueue.main.async {
                                                        self.getAddress(page: sender.accessibilityIdentifier!)
                                                    }
                                                } else if let actualErrorMessage = errorMessage as? String {
                                                    if actualErrorMessage == "Invalid 2FA verification token provided" {
                                                        DispatchQueue.main.async {
                                                            self.nextButtonActivityIndicator.stopAnimating()
                                                            self.nextButtonLabel.alpha = 1
                                                            let alert = UIAlertController(title: "Oops!", message: "Please enter the correct verification code.", preferredStyle: .alert)
                                                            alert.addAction(UIAlertAction(title: "Okay", style: .cancel, handler: nil))
                                                            self.present(alert, animated: true)
                                                        }
                                                    }
                                                }
                                            }
                                        } catch let error as NSError {
                                            print(error)
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
    }
    
    
    func getAddress(page:String) {
        
        let deviceDict = UserDefaults.standard.value(forKey: "device") as? NSDictionary
        if let actualDeviceDict = deviceDict {
            // Some device information exists.
            let clients:[Client] = CacheManager.parseDevice(deviceDict: actualDeviceDict)
            for client in clients {
                if client.id == self.currentClientID {
                    for iban in client.ibanEntities {
                        if iban.id == self.currentIbanID {
                            
                            print(iban.emailToken)
                            print(iban.yourIbanNumber)
                            
                            let message = "I confirm I'm the sole owner of the bitcoin address I provided and I will be sending my own funds to bittr. Order: \(iban.emailToken.prefix(32)). IBAN: \(iban.yourIbanNumber)"
                            let parameters = ["message": message]
                            
                            do {
                                let postData = try JSONSerialization.data(withJSONObject: parameters, options: [])
                                
                                var request = URLRequest(url: URL(string: "https://staging.getbittr.com/api/sign/onchain")!,timeoutInterval: Double.infinity)
                                request.addValue("application/json", forHTTPHeaderField: "Content-Type")
                                request.httpMethod = "POST"
                                request.httpBody = postData
                                
                                let task = URLSession.shared.dataTask(with: request) { data, response, error in
                                    guard let data = data else {
                                        print(String(describing: error))
                                        let alert = UIAlertController(title: "Oops!", message: "Something went wrong creating your account. Please try again.", preferredStyle: .alert)
                                        alert.addAction(UIAlertAction(title: "Okay", style: .cancel, handler: nil))
                                        self.present(alert, animated: true)
                                        return
                                  }
                                  
                                    print(String(data: data, encoding: .utf8)!)
                                    
                                    var dataDictionary:NSDictionary?
                                    if let receivedData = String(data: data, encoding: .utf8)?.data(using: String.Encoding.utf8) {
                                        do {
                                            dataDictionary = try JSONSerialization.jsonObject(with: receivedData, options: []) as? NSDictionary
                                            if let actualDataDict = dataDictionary {
                                                let dataAddress = actualDataDict["address"]
                                                let dataSignature = actualDataDict["signature"]
                                                let dataMessage = actualDataDict["message"]
                                                if let actualDataAddress = dataAddress as? String, let actualDataSignature = dataSignature as? String, let actualDataMessage = dataMessage as? String {
                                                    //CacheManager.addEmailToken(clientID: self.currentClientID, ibanID: self.currentIbanID, emailToken: actualEmailToken)
                                                    DispatchQueue.main.async {
                                                        self.createClient(address: actualDataAddress, signature: actualDataSignature, message: actualDataMessage, page: page, iban: iban)
                                                    }
                                                }
                                            }
                                        } catch let error as NSError {
                                            print(error)
                                        }
                                    }
                                }
                                task.resume()
                            } catch let error as NSError {
                                print(error)
                            }
                        }
                    }
                }
            }
        }
    }
    
    
    func createClient(address:String, signature:String, message:String, page:String, iban:IbanEntity) {
        
        Task {
            
            // Get real onchain address.
            await self.addressViewModel.newFundingAddress()
            let receivedAddress = self.addressViewModel.address
            
            // Get real signature.
            let receivedSignature = try await nodeIDViewModel.signMessage(message: message)
            
            print("Received address: \(receivedAddress)")
            print("Received signature: \(receivedSignature)")
            
            // Send to Bittr.
            self.createBittrAccount(receivedAddress: receivedAddress, receivedSignature: receivedSignature, message: message, page: page, iban: iban)
        }
    }
    
    
    func createBittrAccount(receivedAddress:String, receivedSignature:String, message:String, page:String, iban:IbanEntity) {
        
        let lightningPubKey = LightningNodeService(network: .testnet).nodeId()
        Task {
            do {
                let lightningSignature = try await LightningNodeService(network: .testnet).signMessage(message: message)
                print("Fetched signature: " + lightningSignature)
                
                let parameters = ["email":iban.yourEmail, "email_token":iban.emailToken, "bitcoin_address":receivedAddress/*, "xpub_key":"", "xpub_addr_type":"", "xpub_path":""*/, "initial_address_type":"simple", "category":"ledger", "bitcoin_message":message, "bitcoin_signature":/*receivedSignature*/"Hxzhjz3+eMJNjhJc6iyWJfvD3c/ukn3ygpwW0EfY/KKXaNNwAe0Syis7GxGCTtieui8g7CYg39+nuT55Lb0QYms=", "iban":iban.yourIbanNumber/*, "id":"", "planned_volume":"", "planned_volume_frequency":""*/, "lightning_pubkey":lightningPubKey, "lightning_signature":lightningSignature] as [String:Any]
                
                do {
                    let postData = try JSONSerialization.data(withJSONObject: parameters, options: [])
                    
                    var request = URLRequest(url: URL(string: "https://staging.getbittr.com/api/customer")!,timeoutInterval: Double.infinity)
                    request.addValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.httpMethod = "POST"
                    request.httpBody = postData
                    
                    let task = URLSession.shared.dataTask(with: request) { data, response, error in
                        guard let data = data else {
                            DispatchQueue.main.async {
                                print(String(describing: error))
                                let alert = UIAlertController(title: "Oops!", message: "Something went wrong creating your account. Please try again.", preferredStyle: .alert)
                                alert.addAction(UIAlertAction(title: "Okay", style: .cancel, handler: nil))
                                self.present(alert, animated: true)
                            }
                            return
                        }
                        
                        print(String(data: data, encoding: .utf8)!)
                        
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
                                                CacheManager.addBittrIban(clientID: self.currentClientID, ibanID: self.currentIbanID, ourIban: actualDataOurIban, ourSwift: actualDataSwift, yourCode: actualDataCode)
                                                self.nextButtonActivityIndicator.stopAnimating()
                                                self.nextButtonLabel.alpha = 1
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
                                                let alert = UIAlertController(title: "Oops!", message: "The IBAN you've entered appears to be invalid. Please enter a valid IBAN.", preferredStyle: .alert)
                                                alert.addAction(UIAlertAction(title: "Okay", style: .cancel, handler: {_ in
                                                    let notificationDict:[String: Any] = ["page":"6"]
                                                     NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "signupnext"), object: nil, userInfo: notificationDict) as Notification)
                                                }))
                                                self.present(alert, animated: true)
                                            } else {
                                                self.nextButtonActivityIndicator.stopAnimating()
                                                self.nextButtonLabel.alpha = 1
                                                self.codeTextField.text = nil
                                                let alert = UIAlertController(title: "Oops!", message: "Something went wrong. (\(actualApiMessage).) Please try again later.", preferredStyle: .alert)
                                                alert.addAction(UIAlertAction(title: "Okay", style: .cancel, handler: {_ in
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
                            }
                        }
                    }
                    task.resume()
                } catch let error as NSError {
                    print(error)
                }
            } catch let error as NSError {
                print(error)
            }
        }
        
        
    }
    
    
    @IBAction func resendCodeButtonTapped(_ sender: UIButton) {
        
        if self.counter == 0 {
            
            let deviceDict = UserDefaults.standard.value(forKey: "device") as? NSDictionary
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
                                        let alert = UIAlertController(title: "We've resent our email!", message: "Check your Spam and Promotion folders to see if the code is there.\n\nPlease also check whether \(iban.yourEmail) is correct.", preferredStyle: .alert)
                                        alert.addAction(UIAlertAction(title: "Okay", style: .cancel, handler: nil))
                                        alert.addAction(UIAlertAction(title: "Change email", style: .default, handler: {_ in
                                            let notificationDict:[String: Any] = ["page":"6"]
                                            NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "signupnext"), object: nil, userInfo: notificationDict) as Notification)
                                        }))
                                        self.present(alert, animated: true)
                                    }
                                }
                                task.resume()
                                
                                self.counter = 30
                                Timer.scheduledTimer(timeInterval: 1.0, target: self, selector: #selector(updateCounter), userInfo: nil, repeats: true)
                            }
                        }
                    }
                }
            }
        } else {
            let alert = UIAlertController(title: "", message: "Please wait 30 seconds before requesting another verification code.", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Okay", style: .cancel, handler: nil))
            alert.addAction(UIAlertAction(title: "Change email", style: .default, handler: {_ in
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
    
}
