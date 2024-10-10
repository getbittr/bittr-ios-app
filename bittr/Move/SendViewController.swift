//
//  SendViewController.swift
//  bittr
//
//  Created by Tom Melters on 05/05/2023.
//

import UIKit
import LDKNode
import BitcoinDevKit
import CodeScanner
import AVFoundation
import LDKNodeFFI
import LightningDevKit
import Sentry


class SendViewController: UIViewController, UITextFieldDelegate, AVCaptureMetadataOutputObjectsDelegate {

    // Down button
    @IBOutlet weak var downButton: UIButton!
    
    // Main scroll view
    @IBOutlet weak var scrollView: UIScrollView!
    @IBOutlet weak var scrollViewTrailing: NSLayoutConstraint!
    @IBOutlet weak var contentView: UIView!
    @IBOutlet weak var contentViewBottom: NSLayoutConstraint!
    @IBOutlet weak var backgroundButton: UIButton!
    @IBOutlet weak var centerView: UIView!
    @IBOutlet weak var centerBackgroundButton: UIButton!
    @IBOutlet weak var headerView: UIView!
    @IBOutlet weak var headerLabel: UILabel!
    
    // Main scroll - Switch view
    @IBOutlet weak var switchView: UIView!
    @IBOutlet weak var regularView: UIView!
    @IBOutlet weak var instantView: UIView!
    @IBOutlet weak var regularButton: UIButton!
    @IBOutlet weak var instantButton: UIButton!
    @IBOutlet weak var labelRegular: UILabel!
    @IBOutlet weak var labelInstant: UILabel!
    
    // Main scroll - Items
    @IBOutlet weak var topLabel: UILabel! // Explain items
    @IBOutlet weak var toLabel: UILabel! // Address or Invoice
    @IBOutlet weak var amountLabel: UILabel! // Amount
    
    // Main scroll - To view
    @IBOutlet weak var toView: UIView! // Background
    @IBOutlet weak var toTextField: UITextField! // Text field
    @IBOutlet weak var toTextFieldTop: NSLayoutConstraint! // 5 when closed, 15 when open.
    @IBOutlet weak var toTextFieldHeight: NSLayoutConstraint! // 0 when closed, 25 when open.
    @IBOutlet weak var invoiceLabel: UILabel! // Text label
    @IBOutlet weak var invoiceLabelTop: NSLayoutConstraint! // 10 when closed, 20 when open.
    @IBOutlet weak var backgroundQR: UIView!
    @IBOutlet weak var backgroundPaste: UIView!
    @IBOutlet weak var backgroundKeyboard: UIView!
    @IBOutlet weak var qrButton: UIButton!
    @IBOutlet weak var pasteButton: UIButton!
    @IBOutlet weak var keyboardButton: UIButton!
    
    // Main scroll - Amount view
    @IBOutlet weak var amountView: UIView! // Background
    @IBOutlet weak var amountTextField: UITextField!
    @IBOutlet weak var amountButton: UIButton!
    @IBOutlet weak var availableAmount: UILabel!
    @IBOutlet weak var availableAmountCenterX: NSLayoutConstraint! // 0 or -10
    @IBOutlet weak var availableAmountTop: NSLayoutConstraint! // 10 or -75
    @IBOutlet weak var questionCircle: UIImageView!
    @IBOutlet weak var availableButton: UIButton!
    @IBOutlet weak var availableButtonTop: NSLayoutConstraint! // 0 or -85
    
    // Main scroll - QR scanner
    @IBOutlet weak var scannerView: UIView!
    var captureSession: AVCaptureSession!
    var previewLayer: AVCaptureVideoPreviewLayer!
    var scannerWorks = false
    
    // Main scroll - Next button
    @IBOutlet weak var nextView: UIView! // Background
    @IBOutlet weak var nextViewTop: NSLayoutConstraint!
    @IBOutlet weak var nextSpinner: UIActivityIndicatorView!
    @IBOutlet weak var nextLabel: UILabel! // Next or Manual input
    @IBOutlet weak var nextButton: UIButton!
    
    // Onchain confirm scroll
    @IBOutlet weak var confirmHeaderView: UIView!
    @IBOutlet weak var confirmHeaderLabel: UILabel!
    @IBOutlet weak var confirmTopLabel: UILabel!
    @IBOutlet weak var yellowCard: UIView!
    @IBOutlet weak var confirmToCard: UIView!
    @IBOutlet weak var confirmAmountCard: UIView!
    @IBOutlet weak var confirmAddressLabel: UILabel!
    @IBOutlet weak var confirmAmountLabel: UILabel!
    @IBOutlet weak var confirmEuroLabel: UILabel!
    @IBOutlet weak var editView: UIView!
    @IBOutlet weak var editButton: UIButton!
    @IBOutlet weak var sendView: UIView!
    @IBOutlet weak var sendButton: UIButton!
    @IBOutlet weak var sendSpinner: UIActivityIndicatorView!
    @IBOutlet weak var sendLabel: UILabel!
    @IBOutlet weak var labelAddress: UILabel!
    @IBOutlet weak var labelAmount: UILabel!
    @IBOutlet weak var labelEdit: UILabel!
    
    // Onchain confirm scroll - Fees
    @IBOutlet weak var feesTopLabel: UILabel!
    @IBOutlet weak var fastView: UIView!
    @IBOutlet weak var mediumView: UIView!
    @IBOutlet weak var slowView: UIView!
    @IBOutlet weak var satsFast: UILabel!
    @IBOutlet weak var satsMedium: UILabel!
    @IBOutlet weak var satsSlow: UILabel!
    @IBOutlet weak var eurosFast: UILabel!
    @IBOutlet weak var eurosMedium: UILabel!
    @IBOutlet weak var eurosSlow: UILabel!
    @IBOutlet weak var fastButton: UIButton!
    @IBOutlet weak var mediumButton: UIButton!
    @IBOutlet weak var slowButton: UIButton!
    @IBOutlet weak var slowTimeLabel: UILabel!
    
    // Variables
    var btcAmount:Double = 0.0
    var btclnAmount:Double = 0.0
    var maximumSendableLNSats:Int?
    var maximumSendableOnchainBtc:Double?
    var feeLow:Float = 0.0
    var feeMedium:Float = 0.0
    var feeHigh:Float = 0.0
    var eurValue = 0.0
    var chfValue = 0.0
    var selectedFee = "medium"
    var onchainOrLightning = "onchain"
    var selectedInput = "qr"
    var completedTransaction:Transaction?
    var homeVC:HomeViewController?
    
    override func viewDidLoad() {
        super.viewDidLoad()

        // Button titles
        downButton.setTitle("", for: .normal)
        amountButton.setTitle("", for: .normal)
        availableButton.setTitle("", for: .normal)
        pasteButton.setTitle("", for: .normal)
        backgroundButton.setTitle("", for: .normal)
        centerBackgroundButton.setTitle("", for: .normal)
        nextButton.setTitle("", for: .normal)
        editButton.setTitle("", for: .normal)
        sendButton.setTitle("", for: .normal)
        regularButton.setTitle("", for: .normal)
        instantButton.setTitle("", for: .normal)
        fastButton.setTitle("", for: .normal)
        mediumButton.setTitle("", for: .normal)
        slowButton.setTitle("", for: .normal)
        qrButton.setTitle("", for: .normal)
        keyboardButton.setTitle("", for: .normal)
        
        // Corner radii
        headerView.layer.cornerRadius = 13
        toView.layer.cornerRadius = 13
        amountView.layer.cornerRadius = 13
        nextView.layer.cornerRadius = 13
        confirmHeaderView.layer.cornerRadius = 13
        editView.layer.cornerRadius = 13
        sendView.layer.cornerRadius = 13
        switchView.layer.cornerRadius = 13
        scannerView.layer.cornerRadius = 13
        yellowCard.layer.cornerRadius = 20
        confirmToCard.layer.cornerRadius = 13
        confirmAmountCard.layer.cornerRadius = 13
        fastView.layer.cornerRadius = 13
        mediumView.layer.cornerRadius = 13
        slowView.layer.cornerRadius = 13
        backgroundQR.layer.cornerRadius = 13
        backgroundPaste.layer.cornerRadius = 13
        backgroundKeyboard.layer.cornerRadius = 13
        
        // Shadows
        setShadows(forView: yellowCard)
        setShadows(forView: fastView)
        setShadows(forView: mediumView)
        setShadows(forView: slowView)
        setShadows(forView: backgroundQR)
        setShadows(forView: backgroundPaste)
        setShadows(forView: backgroundKeyboard)
        
        // Text fields
        toTextField.delegate = self
        amountTextField.delegate = self
        amountTextField.addDoneButton(target: self, returnaction: #selector(self.doneButtonTapped))
        
        // Set colors and language
        self.changeColors()
        self.setWords()
        self.setSendAllLabel(forView: "onchain")
    }
    
    func setShadows(forView:UIView) {
        forView.layer.shadowColor = UIColor.black.cgColor
        forView.layer.shadowOffset = CGSize(width: 0, height: 7)
        forView.layer.shadowRadius = 10.0
        forView.layer.shadowOpacity = 0.1
    }
    
    func setSendAllLabel(forView:String) {
        
        if forView == "onchain" {
            // Set "Send all" for onchain transactions.
            if let actualMaximumSendableOnchainBtc = self.maximumSendableOnchainBtc {
                let numberFormatter = NumberFormatter()
                numberFormatter.numberStyle = .decimal
                self.availableAmount.text = "\(Language.getWord(withID:"sendall")): \(numberFormatter.number(from: "\(actualMaximumSendableOnchainBtc)".replacingOccurrences(of: ".", with: Locale.current.decimalSeparator!).replacingOccurrences(of: ",", with: Locale.current.decimalSeparator!))!.decimalValue as NSNumber)".replacingOccurrences(of: "00000000001", with: "").replacingOccurrences(of: "99999999999", with: "").replacingOccurrences(of: "0000000001", with: "").replacingOccurrences(of: "9999999999", with: "")
            } else {
                self.maximumSendableOnchainBtc = self.getMaximumSendableSats()
                let numberFormatter = NumberFormatter()
                numberFormatter.numberStyle = .decimal
                self.availableAmount.text = "\(Language.getWord(withID:"sendall")): \(numberFormatter.number(from: "\(self.maximumSendableOnchainBtc ?? self.btcAmount)".replacingOccurrences(of: ".", with: Locale.current.decimalSeparator!).replacingOccurrences(of: ",", with: Locale.current.decimalSeparator!))!.decimalValue as NSNumber)".replacingOccurrences(of: "00000000001", with: "").replacingOccurrences(of: "99999999999", with: "").replacingOccurrences(of: "0000000001", with: "").replacingOccurrences(of: "9999999999", with: "")
            }
        } else {
            // Set "Send all" for lightning payments.
            if let actualMaxAmount = self.maximumSendableLNSats {
                self.availableAmount.text = "\(Language.getWord(withID:"youcansend")) \(actualMaxAmount) satoshis."
            } else {
                self.availableAmount.text = "\(Language.getWord(withID:"youcansend")) 0 satoshis."
            }
        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillDisappear), name: UIResponder.keyboardWillHideNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillAppear), name: UIResponder.keyboardWillShowNotification, object: nil)
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        if (captureSession?.isRunning == true) {
            captureSession.stopRunning()
        }
    }
    
    @objc func keyboardWillDisappear() {
        
        self.amountButton.alpha = 1
        if self.toTextField.text == nil || self.toTextField.text?.trimmingCharacters(in: .whitespacesAndNewlines) == "" {
            self.toTextFieldHeight.constant = 0
            self.toTextField.alpha = 0
            self.toTextFieldTop.constant = 5
        }
        
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
    
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return false
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
        
        if self.onchainOrLightning == "onchain" {
            // Regular
            let numberFormatter = NumberFormatter()
            numberFormatter.numberStyle = .decimal
            self.amountTextField.text = "\(numberFormatter.number(from: "\(self.maximumSendableOnchainBtc ?? self.btcAmount)".replacingOccurrences(of: ".", with: Locale.current.decimalSeparator!).replacingOccurrences(of: ",", with: Locale.current.decimalSeparator!))!.decimalValue as NSNumber)".replacingOccurrences(of: "00000000001", with: "").replacingOccurrences(of: "99999999999", with: "").replacingOccurrences(of: "0000000001", with: "").replacingOccurrences(of: "9999999999", with: "")
        } else {
            // Instant
            let notificationDict:[String: Any] = ["question":Language.getWord(withID: "limitlightning"),"answer":Language.getWord(withID: "limitlightninganswer"),"type":"lightningsendable"]
            NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "question"), object: nil, userInfo: notificationDict) as Notification)
        }
    }
    
    @IBAction func toPasteButtonTapped(_ sender: UIButton) {
        
        if let actualCaptureSession = captureSession {
            actualCaptureSession.stopRunning()
        }
        self.view.endEditing(true)
        
        if let actualString = UIPasteboard.general.string {
            
            self.selectedInput = "paste"
            
            UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseInOut) {
                
                self.toTextField.alpha = 0
                self.toTextFieldHeight.constant = 0
                self.invoiceLabel.text = actualString
                self.invoiceLabel.alpha = 1
                self.invoiceLabelTop.constant = 20
                self.toTextFieldTop.constant = 5
                
                self.view.layoutIfNeeded()
            }
        }
        
    }
    
    @IBAction func qrButtonTapped(_ sender: UIButton) {
        
        self.selectedInput = "qr"
        self.view.endEditing(true)
        
        self.showScannerView()
    }
    
    @IBAction func keyboardButtonTapped(_ sender: UIButton) {
        
        if let actualCaptureSession = captureSession {
            actualCaptureSession.stopRunning()
        }
        
        self.selectedInput = "keyboard"
        
        UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseInOut) {
            
            if let pastedText = self.invoiceLabel.text {
                self.toTextField.text = pastedText
            }
            
            self.toTextField.alpha = 1
            self.toTextFieldHeight.constant = 25
            self.invoiceLabel.text = nil
            self.invoiceLabel.alpha = 0
            self.toTextFieldTop.constant = 15
            self.invoiceLabelTop.constant = 10
        }
        
        self.toTextField.becomeFirstResponder()
    }
    
    @IBAction func backgroundButtonTapped(_ sender: UIButton) {
        self.view.endEditing(true)
    }
    
    @IBAction func nextButtonTapped(_ sender: UIButton) {
        self.view.endEditing(true)
        
        if self.nextLabel.text == "Next" && self.onchainOrLightning == "onchain" {
            // Check onchain transaction.
            self.checkSendOnchain()
        } else if self.nextLabel.text == "Next" && self.onchainOrLightning == "lightning" {
            // Confirm lightning payment.
            self.confirmLightningTransaction()
        } else if self.nextLabel.text == "Manual input", self.onchainOrLightning == "onchain" {
            // Hide QR scanner, show onchain.
            self.hideScannerView(forView: "onchain")
        } else if self.nextLabel.text == "Manual input", self.onchainOrLightning == "lightning" {
            // Hide QR scanner, show lightning.
            self.hideScannerView(forView: "lightning")
        }
    }
    
    @IBAction func editButtonTapped(_ sender: UIButton) {
        // Slide back to leftmost scroll view.
        UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseInOut) {
            NSLayoutConstraint.deactivate([self.scrollViewTrailing])
            self.scrollViewTrailing = NSLayoutConstraint(item: self.scrollView, attribute: .trailing, relatedBy: .equal, toItem: self.view, attribute: .trailing, multiplier: 1, constant: 0)
            NSLayoutConstraint.activate([self.scrollViewTrailing])
            self.view.layoutIfNeeded()
        }
    }
    
    func checkInternetConnection() -> Bool {
        // Check internet connection.
        if !Reachability.isConnectedToNetwork() {
            // User not connected to internet.
            let alert = UIAlertController(title: Language.getWord(withID: "checkyourconnection"), message: Language.getWord(withID: "trytoconnect"), preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: Language.getWord(withID: "okay"), style: .cancel, handler: nil))
            self.present(alert, animated: true)
            return false
        } else {
            return true
        }
    }
    
    @IBAction func sendButtonTapped(_ sender: UIButton) {
        // Send onchain transaction.
        if self.checkInternetConnection() {
            self.confirmSendOnchain()
        }
    }
    
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        
        // Show new transaction in TransactionVC.
        if segue.identifier == "SendToTransaction" {
            let transactionVC = segue.destination as? TransactionViewController
            if let actualTransactionVC = transactionVC {
                if let actualCompletedTransaction = self.completedTransaction {
                    actualTransactionVC.tappedTransaction = actualCompletedTransaction
                    actualTransactionVC.eurValue = (CacheManager.getCachedData(key: "eurvalue") as? CGFloat)!
                    actualTransactionVC.chfValue = (CacheManager.getCachedData(key: "chfvalue") as? CGFloat)!
                }
            }
        }
    }
    
    
    @IBAction func switchTapped(_ sender: UIButton) {
        
        // Reset fields.
        self.resetFields()
        
        // Switch view.
        self.onchainOrLightning = sender.accessibilityIdentifier ?? self.onchainOrLightning
        self.hideScannerView(forView: self.onchainOrLightning)
    }
    
    @IBAction func feeButtonTapped(_ sender: UIButton) {
        self.switchFeeSelection(tappedFee: sender.accessibilityIdentifier!)
    }
    
    func changeColors() {
        
        self.view.backgroundColor = Colors.getColor(color: "yellowandgrey")
        self.topLabel.textColor = Colors.getColor(color: "black")
        self.toLabel.textColor = Colors.getColor(color: "black")
        self.amountLabel.textColor = Colors.getColor(color: "black")
        self.availableAmount.textColor = Colors.getColor(color: "black")
        self.questionCircle.tintColor = Colors.getColor(color: "black")
        
        self.confirmTopLabel.textColor = Colors.getColor(color: "black")
        self.yellowCard.backgroundColor = Colors.getColor(color: "cardbackground")
        self.confirmToCard.backgroundColor = Colors.getColor(color: "whiteorlightblue")
        self.confirmAmountCard.backgroundColor = Colors.getColor(color: "whiteorlightblue")
        self.confirmAddressLabel.textColor = Colors.getColor(color: "black")
        self.confirmAmountLabel.textColor = Colors.getColor(color: "black")
        self.confirmEuroLabel.textColor = Colors.getColor(color: "black")
        self.feesTopLabel.textColor = Colors.getColor(color: "black")
    }
    
}

extension UITextField {
    
    func addDoneButton(target:Any, returnaction:Selector) {
        
        let toolbar:UIToolbar = UIToolbar()
        toolbar.barStyle = .default
        toolbar.items = [
                UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: self, action: nil),
                UIBarButtonItem(title: Language.getWord(withID: "done"), style: .done, target: target, action: returnaction)
            ]
        toolbar.sizeToFit()
        self.inputAccessoryView = toolbar
    }
}
