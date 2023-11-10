//
//  SendViewController.swift
//  bittr
//
//  Created by Tom Melters on 05/05/2023.
//

import UIKit
import LDKNode

class SendViewController: UIViewController, UITextFieldDelegate {

    @IBOutlet weak var downButton: UIButton!
    @IBOutlet weak var headerView: UIView!
    @IBOutlet weak var fromView: UIView!
    @IBOutlet weak var toView: UIView!
    @IBOutlet weak var amountView: UIView!
    @IBOutlet weak var nextView: UIView!
    
    @IBOutlet weak var fromButton: UIButton!
    @IBOutlet weak var fromLabel: UILabel!
    @IBOutlet weak var toTextField: UITextField!
    @IBOutlet weak var toButton: UIButton!
    @IBOutlet weak var amountTextField: UITextField!
    @IBOutlet weak var availableAmount: UILabel!
    @IBOutlet weak var amountButton: UIButton!
    @IBOutlet weak var availableButton: UIButton!
    @IBOutlet weak var clipboardWidth: NSLayoutConstraint!
    @IBOutlet weak var toTextFieldTrailing: NSLayoutConstraint!
    @IBOutlet weak var pasteButton: UIButton!
    @IBOutlet weak var nextButton: UIButton!
    
    @IBOutlet weak var contentViewBottom: NSLayoutConstraint!
    @IBOutlet weak var contentView: UIView!
    @IBOutlet weak var scrollView: UIScrollView!
    
    @IBOutlet weak var backgroundButton: UIButton!
    @IBOutlet weak var centerBackgroundButton: UIButton!
    
    @IBOutlet weak var scrollViewTrailing: NSLayoutConstraint!
    @IBOutlet weak var confirmHeaderView: UIView!
    @IBOutlet weak var editView: UIView!
    @IBOutlet weak var editButton: UIButton!
    @IBOutlet weak var sendView: UIView!
    @IBOutlet weak var fromConfirmation: UILabel!
    @IBOutlet weak var toConfirmation: UILabel!
    @IBOutlet weak var amountConfirmation: UILabel!
    @IBOutlet weak var feesConfirmation: UILabel!
    @IBOutlet weak var totalConfirmation: UILabel!
    @IBOutlet weak var sendButton: UIButton!
    
    var btcAmount = 0.07255647
    var btclnAmount = 0.02266301
    var presetAmount:Double?
    
    var lightningNodeService:LightningNodeService?
    
    override func viewDidLoad() {
        super.viewDidLoad()

        downButton.setTitle("", for: .normal)
        fromButton.setTitle("", for: .normal)
        toButton.setTitle("", for: .normal)
        amountButton.setTitle("", for: .normal)
        availableButton.setTitle("", for: .normal)
        pasteButton.setTitle("", for: .normal)
        backgroundButton.setTitle("", for: .normal)
        centerBackgroundButton.setTitle("", for: .normal)
        nextButton.setTitle("", for: .normal)
        editButton.setTitle("", for: .normal)
        sendButton.setTitle("", for: .normal)
        
        headerView.layer.cornerRadius = 13
        fromView.layer.cornerRadius = 13
        toView.layer.cornerRadius = 13
        amountView.layer.cornerRadius = 13
        nextView.layer.cornerRadius = 13
        confirmHeaderView.layer.cornerRadius = 13
        editView.layer.cornerRadius = 13
        sendView.layer.cornerRadius = 13
        
        toTextField.delegate = self
        amountTextField.delegate = self
        amountTextField.addDoneButton(target: self, returnaction: #selector(self.doneButtonTapped))
        
        let numberFormatter = NumberFormatter()
        numberFormatter.numberStyle = .decimal
        self.availableAmount.text = "Send all: \(numberFormatter.number(from: "\(self.btcAmount)".replacingOccurrences(of: ".", with: Locale.current.decimalSeparator!).replacingOccurrences(of: ",", with: Locale.current.decimalSeparator!))!.decimalValue as NSNumber)"
        
        if let actualPresetAmount = presetAmount {
            
            self.fromLabel.text = "My BTCLN wallet"
            self.toTextField.text = "My BTC wallet"
            self.availableAmount.text = "Send all: \(numberFormatter.number(from: "\(self.btclnAmount)".replacingOccurrences(of: ".", with: Locale.current.decimalSeparator!).replacingOccurrences(of: ",", with: Locale.current.decimalSeparator!))!.decimalValue as NSNumber)"
            self.clipboardWidth.constant = 0
            self.toTextFieldTrailing.constant = 0
            self.amountTextField.text = String(actualPresetAmount)
        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillDisappear), name: UIResponder.keyboardWillHideNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillAppear), name: UIResponder.keyboardWillShowNotification, object: nil)
    }
    
    @objc func keyboardWillDisappear() {
        
        self.toButton.alpha = 1
        self.amountButton.alpha = 1
        
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
    
    @IBAction func downButtonTapped(_ sender: UIButton) {
        self.dismiss(animated: true, completion: nil)
    }
    
    @IBAction func fromButtonTapped(_ sender: UIButton) {
        
        let numberFormatter = NumberFormatter()
        numberFormatter.numberStyle = .decimal
        
        let actionSheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        let btcOption = UIAlertAction(title: "My BTC wallet", style: .default) { (action) in
            self.fromLabel.text = "My BTC wallet"
            self.toTextField.text = ""
            self.availableAmount.text = "Send all: \(numberFormatter.number(from: "\(self.btcAmount)")!.decimalValue as NSNumber)"
            self.clipboardWidth.constant = 20
            self.toTextFieldTrailing.constant = -10
        }
        let btclnOption = UIAlertAction(title: "My BTCLN wallet", style: .default) { (action) in
            
            let alert = UIAlertController(title: "Unavailable", message: "This feature is still being worked on.", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Okay", style: .cancel, handler: nil))
            self.present(alert, animated: true)
            
            return
            
            /*self.fromLabel.text = "My BTCLN wallet"
            self.toTextField.text = "My BTC wallet"
            self.availableAmount.text = "Send all: \(numberFormatter.number(from: "\(self.btclnAmount)")!.decimalValue as NSNumber)"
            self.clipboardWidth.constant = 0
            self.toTextFieldTrailing.constant = 0*/
        }
        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel, handler: nil)
        actionSheet.addAction(btcOption)
        actionSheet.addAction(btclnOption)
        actionSheet.addAction(cancelAction)
        present(actionSheet, animated: true, completion: nil)
    }
    
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return false
    }
    
    @IBAction func toButtonTapped(_ sender: UIButton) {
        
        if toTextField.text != "My BTC wallet" {
            self.toTextField.becomeFirstResponder()
            self.toButton.alpha = 0
        }
    }
    
    @IBAction func amountButtonTapped(_ sender: UIButton) {
        self.amountTextField.becomeFirstResponder()
        self.amountButton.alpha = 0
    }
    
    @objc func doneButtonTapped() {
        self.amountTextField.resignFirstResponder()
        self.amountButton.alpha = 1
    }
    
    @IBAction func availableButtonTapped(_ sender: UIButton) {
        
        let numberFormatter = NumberFormatter()
        numberFormatter.numberStyle = .decimal
        if self.fromLabel.text == "My BTC wallet" {
            self.amountTextField.text = "\(numberFormatter.number(from: "\(self.btcAmount)".replacingOccurrences(of: ".", with: Locale.current.decimalSeparator!).replacingOccurrences(of: ",", with: Locale.current.decimalSeparator!))!.decimalValue as NSNumber)"
        } else {
            self.amountTextField.text = "\(numberFormatter.number(from: "\(self.btclnAmount)".replacingOccurrences(of: ".", with: Locale.current.decimalSeparator!).replacingOccurrences(of: ",", with: Locale.current.decimalSeparator!))!.decimalValue as NSNumber)"
        }
    }
    
    @IBAction func toPasteButtonTapped(_ sender: UIButton) {
        
        self.toTextField.text = UIPasteboard.general.string
    }
    
    @IBAction func backgroundButtonTapped(_ sender: UIButton) {
        
        self.view.endEditing(true)
    }
    
    @IBAction func nextButtonTapped(_ sender: UIButton) {
        
        let formatter = NumberFormatter()
        formatter.decimalSeparator = "."
        if self.toTextField.text == nil || self.toTextField.text?.trimmingCharacters(in: .whitespaces) == "" || self.amountTextField.text == nil || self.amountTextField.text?.trimmingCharacters(in: .whitespacesAndNewlines) == "" || CGFloat(truncating: formatter.number(from: self.amountTextField.text?.replacingOccurrences(of: ",", with: ".") ?? "0.0")!) == 0  {
            
            // Fields are left empty or the amount if set to zero.
            
        } else if CGFloat(truncating: formatter.number(from: self.amountTextField.text?.replacingOccurrences(of: ",", with: ".") ?? "0.0")!) > self.btcAmount {
            
            // Insufficient funds available.
            let alert = UIAlertController(title: "Oops!", message: "Make sure the amount of BTC you wish to send is within your spendable balance.", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Okay", style: .cancel, handler: nil))
            self.present(alert, animated: true)
        } else {
            
            self.fromConfirmation.text = self.fromLabel.text
            self.toConfirmation.text = self.toTextField.text
            self.amountConfirmation.text = self.amountTextField.text
            self.feesConfirmation.text = "0.0"
            self.totalConfirmation.text = self.amountTextField.text
            
            UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseInOut) {
                
                NSLayoutConstraint.deactivate([self.scrollViewTrailing])
                self.scrollViewTrailing = NSLayoutConstraint(item: self.scrollView, attribute: .trailing, relatedBy: .equal, toItem: self.view, attribute: .leading, multiplier: 1, constant: 0)
                NSLayoutConstraint.activate([self.scrollViewTrailing])
                self.view.layoutIfNeeded()
            }
        }
    }
    
    @IBAction func editButtonTapped(_ sender: UIButton) {
        
        UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseInOut) {
            
            NSLayoutConstraint.deactivate([self.scrollViewTrailing])
            self.scrollViewTrailing = NSLayoutConstraint(item: self.scrollView, attribute: .trailing, relatedBy: .equal, toItem: self.view, attribute: .trailing, multiplier: 1, constant: 0)
            NSLayoutConstraint.activate([self.scrollViewTrailing])
            self.view.layoutIfNeeded()
        }
    }
    
    @IBAction func sendButtonTapped(_ sender: UIButton) {
        
        if let actualLightningNodeService = self.lightningNodeService {
            do {
                let transactionID = try actualLightningNodeService.sendToOnchainAddress(address: "tb1qw2c3lxufxqe2x9s4rdzh65tpf4d7fssjgh8nv6", amountMsat: 10)
                print("Successful transaction.")
                self.dismiss(animated: true)
            } catch let error as NSError {
                print("Some error occurred: \(error.localizedDescription)")
                self.dismiss(animated: true)
            }
        } else {
            print("LightningNodeService wasn't set.")
            self.dismiss(animated: true)
        }
    }
    
}

extension UITextField {
    
    func addDoneButton(target:Any, returnaction:Selector) {
        
        let toolbar:UIToolbar = UIToolbar()
        toolbar.barStyle = .default
        toolbar.items = [
                UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: self, action: nil),
                UIBarButtonItem(title: "Done", style: .done, target: target, action: returnaction)
            ]
        toolbar.sizeToFit()
        self.inputAccessoryView = toolbar
    }
}
