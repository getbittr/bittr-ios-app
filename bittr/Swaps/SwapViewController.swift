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
    var pendingInvoice:Bolt11Invoice?
    var swapDictionary:NSDictionary?
    var webSocketManager:WebSocketManager?
    
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
        
        // TODO: Hide after testing
        /*self.swapDictionary = ["bip21":"bitcoin:bcrt1pjrfwgwzqx09sefe870shg4ly5nd94t4cswgv8mh4z33v83325f5sl5epem?amount=0.00060362&label=Send%20to%20BTC%20lightning","acceptZeroConf":false,"expectedAmount":60362,"id":"7NC16YmWQZm5","address":"bcrt1pjrfwgwzqx09sefe870shg4ly5nd94t4cswgv8mh4z33v83325f5sl5epem","swapTree":["claimLeaf":["version":192,"output":"a914d38a55fdd2cf0e1205ceaf84a8552935230096238820a24359002d3450b1e28f775e2cb89ccb2b06cb4d137925c16899964d0ab2ed01ac"],"refundLeaf":["version":192,"output":"204ea6d0ca3bef8ad17d716c9cea306596e8088b5c03abd1804e9d6c574d737c88ad020f02b1"]],"claimPublicKey":"02a24359002d3450b1e28f775e2cb89ccb2b06cb4d137925c16899964d0ab2ed01","timeoutBlockHeight":527]
        self.didCompleteOnchainTransaction(swapDictionary:self.swapDictionary!)*/
        /*SwapManager.checkSwapStatus("7NC16YmWQZm5") { status in
            print("172 Status: \(status ?? "No status available")")
        }*/
        
        if self.stringToNumber(self.amountTextField.text) != 0 {
            if Int(self.stringToNumber(self.amountTextField.text)) > self.homeVC!.coreVC!.bittrChannel!.receivableMaximum {
                // You can't receive or send this much.
                self.showAlert(title: Language.getWord(withID: "swapfunds2"), message: Language.getWord(withID: "swapamountexceeded").replacingOccurrences(of: "<amount>", with: "\(self.homeVC!.coreVC!.bittrChannel!.receivableMaximum)"), buttons: [Language.getWord(withID: "okay")], actions: nil)
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
    
    func confirmExpectedFees(feeHigh:Float, onchainFees:Int, lightningFees:Int, swapDictionary:NSDictionary, createdInvoice:Bolt11Invoice) {
        
        self.pendingInvoice = createdInvoice
        
        var currency = "€"
        var correctAmount = self.homeVC!.coreVC!.eurValue
        if UserDefaults.standard.value(forKey: "currency") as? String == "CHF" {
            correctAmount = self.homeVC!.coreVC!.chfValue
            currency = "CHF"
        }
        var convertedFees = "\(CGFloat(Int(CGFloat(onchainFees + lightningFees)/100000000*correctAmount*100))/100)".replacingOccurrences(of: ".", with: ",")
        if convertedFees.split(separator: ",")[1].count == 1 {
            convertedFees = convertedFees + "0"
        }
        var convertedAmount = "\(Int((CGFloat(self.amountToBeSent ?? 0)/100000000*correctAmount).rounded()))"
        
        let alert = UIAlertController(title: Language.getWord(withID: "swapfunds2"), message: Language.getWord(withID: "swapfunds3").replacingOccurrences(of: "<feesamount>", with: "\(onchainFees + lightningFees)").replacingOccurrences(of: "<convertedfees>", with: "\(currency) \(convertedFees)").replacingOccurrences(of: "<amount>", with: "\(self.amountToBeSent ?? 0)").replacingOccurrences(of: "<convertedamount>", with: "\(currency) \(convertedAmount)"), preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: Language.getWord(withID: "cancel"), style: .cancel, handler: nil))
        alert.addAction(UIAlertAction(title: Language.getWord(withID: "proceed"), style: .default, handler: { _ in
            
            SwapManager.sendOnchainPayment(feeHigh: feeHigh, onchainFees: onchainFees, lightningFees: lightningFees, receivedDictionary: swapDictionary, delegate: self)
        }))
        self.present(alert, animated: true)
    }
    
    func didCompleteOnchainTransaction(swapDictionary:NSDictionary) {
        
        // It may take significant time (e.g. 30 minutes) for the onchain transaction to be confirmed. We need to wait for this confirmation.
        
        self.swapDictionary = swapDictionary
        
        if let swapID = swapDictionary["id"] as? String {
            self.webSocketManager = WebSocketManager()
            self.webSocketManager!.delegate = self
            self.webSocketManager!.swapID = swapID
            self.webSocketManager!.connect()
        }
    }
    
    func receivedStatusUpdate(status:String) {
        if status == "transaction.claim.pending" {
            
            // When status is transaction.claim.pending, get preimage details from API /swap/submarine/swapID/claim to verify that the Lightning payment has been made.
            
            if let swapID = self.swapDictionary?["id"] as? String {
                SwapManager.checkPreimageDetails(swapID: swapID, delegate: self)
            }
            
        } else if status == "invoice.failedToPay" || status == "transaction.lockupFailed" {
            
            // Boltz's payment has failed and we want to get a refund our onchain transaction. Get a partial signature through /swap/submarine/swapID/refund. Or a scriptpath refund can be done after the locktime of the swap expires.
        }
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
