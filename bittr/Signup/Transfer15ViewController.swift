//
//  Transfer15ViewController.swift
//  bittr
//
//  Created by Tom Melters on 15/06/2023.
//

import UIKit

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
                                                if let actualEmailToken = emailToken as? String {
                                                    CacheManager.addEmailToken(clientID: self.currentClientID, ibanID: self.currentIbanID, emailToken: actualEmailToken)
                                                }
                                            }
                                        } catch let error as NSError {
                                            print(error)
                                        }
                                    }
                                }
                                task.resume()
                                
                                
                                let notificationDict:[String: Any] = ["page":sender.accessibilityIdentifier]
                                 NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "signupnext"), object: nil, userInfo: notificationDict) as Notification)
                            }
                        }
                    }
                }
            }
        }
    }
    
    @IBAction func resendCodeButtonTapped(_ sender: UIButton) {
        
        let alert = UIAlertController(title: "Got it!", message: "We've resent your verification code.\n\nCheck your Spam and Promotion folders to make sure the code isn't there.", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Okay", style: .cancel, handler: nil))
        self.present(alert, animated: true)
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
