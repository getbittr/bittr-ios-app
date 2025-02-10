//
//  SwapViewController.swift
//  bittr
//
//  Created by Tom Melters on 24/01/2025.
//

import UIKit
import LDKNode

class SwapViewController: UIViewController, UITextFieldDelegate {

    // General
    @IBOutlet weak var downButton: UIButton!
    @IBOutlet weak var mainScrollView: UIScrollView!
    @IBOutlet weak var mainContentView: UIView!
    @IBOutlet weak var mainContentViewBottom: NSLayoutConstraint!
    @IBOutlet weak var contentBackground: UIButton!
    
    // Card contents
    @IBOutlet weak var centerCard: UIView!
    @IBOutlet weak var centerBackground: UIButton!
    @IBOutlet weak var swapIcon: UIImageView!
    @IBOutlet weak var topLabel: UILabel!
    @IBOutlet weak var subtitleLabel: UILabel!
    @IBOutlet weak var moveLabel: UILabel!
    @IBOutlet weak var amountTextField: UITextField!
    
    // From view
    @IBOutlet weak var fromView: UIView!
    @IBOutlet weak var fromLabel: UILabel!
    @IBOutlet weak var fromButton: UIButton!
    
    // Available view
    @IBOutlet weak var availableAmountLabel: UILabel!
    @IBOutlet weak var availableButton: UIButton!
    @IBOutlet weak var questionMark: UIImageView!
    
    // Next view
    @IBOutlet weak var nextView: UIView!
    @IBOutlet weak var nextLabel: UILabel!
    @IBOutlet weak var nextButton: UIButton!
    @IBOutlet weak var nextSpinner: UIActivityIndicatorView!
    
    // Variables
    var homeVC:HomeViewController?
    var swapDirection = 0
    var amountToBeSent:Int?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Button titles
        self.downButton.setTitle("", for: .normal)
        self.centerBackground.setTitle("", for: .normal)
        self.contentBackground.setTitle("", for: .normal)
        self.nextButton.setTitle("", for: .normal)
        self.availableButton.setTitle("", for: .normal)
        self.fromButton.setTitle("", for: .normal)
        
        // Center card styling
        self.centerCard.layer.cornerRadius = 13
        self.centerCard.layer.shadowColor = UIColor.black.cgColor
        self.centerCard.layer.shadowOffset = CGSize(width: 0, height: 7)
        self.centerCard.layer.shadowRadius = 10.0
        self.centerCard.layer.shadowOpacity = 0.1
        
        // Amount text field
        self.amountTextField.delegate = self
        self.amountTextField.addDoneButton(target: self, returnaction: #selector(self.backgroundTapped))
        self.amountTextField.layer.cornerRadius = 8
        self.amountTextField.layer.shadowColor = UIColor.black.cgColor
        self.amountTextField.layer.shadowOffset = CGSize(width: 0, height: 7)
        self.amountTextField.layer.shadowRadius = 10.0
        self.amountTextField.layer.shadowOpacity = 0.1
        
        // From view
        self.fromView.layer.cornerRadius = 8
        self.fromView.layer.shadowColor = UIColor.black.cgColor
        self.fromView.layer.shadowOffset = CGSize(width: 0, height: 7)
        self.fromView.layer.shadowRadius = 10.0
        self.fromView.layer.shadowOpacity = 0.1
        
        // Next view
        self.nextView.layer.cornerRadius = 13
        
        // Available amount
        if let actualChannel = self.homeVC?.coreVC?.bittrChannel {
            self.availableAmountLabel.text = Language.getWord(withID: "satsatatime").replacingOccurrences(of: "<amount>", with: "\(actualChannel.receivableMaximum)")
        }

        // Set colors and language
        self.changeColors()
        self.setLanguage()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillDisappear), name: UIResponder.keyboardWillHideNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillAppear), name: UIResponder.keyboardWillShowNotification, object: nil)
    }
    
    @objc func keyboardWillDisappear() {
        
        NSLayoutConstraint.deactivate([self.mainContentViewBottom])
        self.mainContentViewBottom = NSLayoutConstraint(item: self.mainContentView!, attribute: .bottom, relatedBy: .equal, toItem: self.mainScrollView, attribute: .bottom, multiplier: 1, constant: 0)
        NSLayoutConstraint.activate([self.mainContentViewBottom])
        self.view.layoutIfNeeded()
    }
    
    @objc func keyboardWillAppear(_ notification:Notification) {
        
        if let keyboardSize = (notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue {
            
            let keyboardHeight = keyboardSize.height
            
            NSLayoutConstraint.deactivate([self.mainContentViewBottom])
            self.mainContentViewBottom = NSLayoutConstraint(item: self.mainContentView!, attribute: .bottom, relatedBy: .equal, toItem: self.mainScrollView, attribute: .bottom, multiplier: 1, constant: -keyboardHeight)
            NSLayoutConstraint.activate([self.mainContentViewBottom])
            
            self.view.layoutIfNeeded()
        }
    }
    
    @IBAction func downButtonTapped(_ sender: UIButton) {
        self.view.endEditing(true)
        self.dismiss(animated: true)
    }
    
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        self.view.endEditing(true)
        return false
    }
    
    @IBAction func fromButtonTapped(_ sender: UIButton) {
        self.view.endEditing(true)
        
        let actionSheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        let onchainToLightning = UIAlertAction(title: Language.getWord(withID: "onchaintolightning"), style: .default) { (action) in
            
            self.fromLabel.text = Language.getWord(withID: "onchaintolightning")
            self.swapDirection = 0
        }
        let lightningToOnchain = UIAlertAction(title: Language.getWord(withID: "lightningtoonchain"), style: .default) { (action) in
            
            self.fromLabel.text = Language.getWord(withID: "lightningtoonchain")
            self.swapDirection = 1
        }
        let cancelAction = UIAlertAction(title: Language.getWord(withID: "cancel"), style: .cancel, handler: nil)
        actionSheet.addAction(onchainToLightning)
        actionSheet.addAction(lightningToOnchain)
        actionSheet.addAction(cancelAction)
        present(actionSheet, animated: true, completion: nil)
    }
    
    @IBAction func availableAmountTapped(_ sender: UIButton) {
        self.view.endEditing(true)
        
        let notificationDict:[String: Any] = ["question":Language.getWord(withID: "limitlightning"),"answer":Language.getWord(withID: "limitlightninganswer"),"type":"lightningsendable"]
        NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "question"), object: nil, userInfo: notificationDict) as Notification)
    }
    
    @IBAction func nextTapped(_ sender: UIButton) {
        self.view.endEditing(true)
        
        if self.stringToNumber(self.amountTextField.text) != 0 {
            if Int(self.stringToNumber(self.amountTextField.text)) > self.homeVC!.coreVC!.bittrChannel!.receivableMaximum {
                // You can't receive or send this much.
                self.showAlert(Language.getWord(withID: "swapfunds2"), Language.getWord(withID: "swapamountexceeded").replacingOccurrences(of: "<amount>", with: "\(self.homeVC!.coreVC!.bittrChannel!.receivableMaximum)"), Language.getWord(withID: "okay"))
            } else {
                self.amountToBeSent = Int(self.stringToNumber(self.amountTextField.text))
                if self.swapDirection == 0 {
                    // Onchain to Lightning.
                    Task {
                        await SwapManager.onchainToLightning(amountMsat: UInt64(Int(self.stringToNumber(self.amountTextField.text))*1000), delegate: self)
                    }
                } else {
                    // Lightning to Onchain
                    Task {
                        await SwapManager.lightningToOnchain(amountSat: Int(self.stringToNumber(self.amountTextField.text)), delegate: self)
                    }
                }
            }
        }
    }
    
    func confirmExpectedFees(expectedFees:Int, swapDictionary:NSDictionary, createdInvoice:Bolt11Invoice) {
        
        var currency = "€"
        var correctAmount = self.homeVC!.coreVC!.eurValue
        if UserDefaults.standard.value(forKey: "currency") as? String == "CHF" {
            correctAmount = self.homeVC!.coreVC!.chfValue
            currency = "CHF"
        }
        var convertedFees = "\(CGFloat(Int(CGFloat(expectedFees)/100000000*correctAmount*100))/100)".replacingOccurrences(of: ".", with: ",")
        if convertedFees.split(separator: ",")[1].count == 1 {
            convertedFees = convertedFees + "0"
        }
        var convertedAmount = "\(Int((CGFloat(self.amountToBeSent ?? 0)/100000000*correctAmount).rounded()))"
        
        let alert = UIAlertController(title: Language.getWord(withID: "swapfunds2"), message: Language.getWord(withID: "swapfunds3").replacingOccurrences(of: "<feesamount>", with: "\(expectedFees)").replacingOccurrences(of: "<convertedfees>", with: "\(currency) \(convertedFees)").replacingOccurrences(of: "<amount>", with: "\(self.amountToBeSent ?? 0)").replacingOccurrences(of: "<convertedamount>", with: "\(currency) \(convertedAmount)"), preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: Language.getWord(withID: "cancel"), style: .cancel, handler: nil))
        alert.addAction(UIAlertAction(title: Language.getWord(withID: "proceed"), style: .default, handler: { _ in
            Task {
                await SwapManager.sendOnchainTransaction(receivedDictionary: swapDictionary)
            }
        }))
        self.present(alert, animated: true)
    }
    
    @IBAction func backgroundTapped(_ sender: UIButton) {
        self.view.endEditing(true)
    }
    
    func setLanguage() {
        self.topLabel.text = Language.getWord(withID: "swapfunds")
        self.subtitleLabel.text = Language.getWord(withID: "swapsubtitle")
        self.moveLabel.text = Language.getWord(withID: "move")
        self.nextLabel.text = Language.getWord(withID: "next")
        self.fromLabel.text = Language.getWord(withID: "onchaintolightning")
    }
    
    func changeColors() {
        self.view.backgroundColor = Colors.getColor("yelloworblue1")
        self.topLabel.textColor = Colors.getColor("whiteoryellow")
        self.subtitleLabel.textColor = Colors.getColor("blackorwhite")
        self.moveLabel.textColor = Colors.getColor("blackoryellow")
        self.centerCard.backgroundColor = Colors.getColor("yelloworblue1")
        self.availableAmountLabel.textColor = Colors.getColor("blackorwhite")
        self.questionMark.tintColor = Colors.getColor("blackorwhite")
        self.amountTextField.backgroundColor = Colors.getColor("white0.7orblue2")
        self.fromView.backgroundColor = Colors.getColor("whiteorblue3")
        self.fromLabel.textColor = Colors.getColor("blackorwhite")
        
        self.amountTextField.attributedPlaceholder = NSAttributedString(
            string: Language.getWord(withID: "enteramountofsatoshis"),
            attributes: [NSAttributedString.Key.foregroundColor: Colors.getColor("grey2orwhite0.7")]
        )
        
        if CacheManager.darkModeIsOn() {
            self.swapIcon.image = UIImage(named: "iconswap")
        } else {
            self.swapIcon.image = UIImage(named: "iconswapwhite")
        }
    }

}
