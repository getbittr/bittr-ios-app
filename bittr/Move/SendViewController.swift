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
    
    // Main scroll - Switch view
    @IBOutlet weak var switchView: UIView!
    @IBOutlet weak var regularView: UIView!
    @IBOutlet weak var instantView: UIView!
    @IBOutlet weak var regularButton: UIButton!
    @IBOutlet weak var instantButton: UIButton!
    
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
    
    // Onchain confirm scroll - Fees
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
    
    // Variables
    var btcAmount = 0.07255647
    var btclnAmount = 0.02266301
    var presetAmount:Double?
    var maximumSendableLNSats:Int?
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
        
        setSendAllLabel()
    }
    
    func setShadows(forView:UIView) {
        forView.layer.shadowColor = UIColor.black.cgColor
        forView.layer.shadowOffset = CGSize(width: 0, height: 7)
        forView.layer.shadowRadius = 10.0
        forView.layer.shadowOpacity = 0.1
    }
    
    func setSendAllLabel() {
        
        // Set "Send all" for onchain transactions.
        let numberFormatter = NumberFormatter()
        numberFormatter.numberStyle = .decimal
        self.availableAmount.text = "Send all: \(numberFormatter.number(from: "\(self.btcAmount)".replacingOccurrences(of: ".", with: Locale.current.decimalSeparator!).replacingOccurrences(of: ",", with: Locale.current.decimalSeparator!))!.decimalValue as NSNumber)".replacingOccurrences(of: "00000000001", with: "").replacingOccurrences(of: "99999999999", with: "").replacingOccurrences(of: "0000000001", with: "").replacingOccurrences(of: "9999999999", with: "")
    }
    
    override func viewWillAppear(_ animated: Bool) {
        
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillDisappear), name: UIResponder.keyboardWillHideNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillAppear), name: UIResponder.keyboardWillShowNotification, object: nil)
        
        if (captureSession?.isRunning == false) {
            DispatchQueue.global(qos: .background).async {
                self.captureSession.startRunning()
            }
        }
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
            self.amountTextField.text = "\(numberFormatter.number(from: "\(self.btcAmount)".replacingOccurrences(of: ".", with: Locale.current.decimalSeparator!).replacingOccurrences(of: ",", with: Locale.current.decimalSeparator!))!.decimalValue as NSNumber)"
        } else {
            // Instant
            let notificationDict:[String: Any] = ["question":"why a limit for instant payments?","answer":"Your bittr wallet consists of a bitcoin wallet (for regular payments) and a bitcoin lightning channel (for instant payments).\n\nIf you've purchased satoshis into your lightning channel, you can use those to pay lightning invoices.\n\nYou cannot make instant payments that exceed the funds in your lightning channel.","type":"lightningsendable"]
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
        
        if fixQrScanner() == true {
            // Open QR scanner.
            UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseInOut) {
                self.toLabel.alpha = 0
                self.toView.alpha = 0
                self.pasteButton.alpha = 0
                self.amountView.alpha = 0
                self.amountLabel.alpha = 0
                self.availableAmount.alpha = 0
                self.availableButton.alpha = 0
                self.scannerView.alpha = 1
                self.nextLabel.text = "Manual input"
                
                NSLayoutConstraint.deactivate([self.nextViewTop])
                self.nextViewTop = NSLayoutConstraint(item: self.nextView, attribute: .top, relatedBy: .equal, toItem: self.scannerView, attribute: .bottom, multiplier: 1, constant: 30)
                NSLayoutConstraint.activate([self.nextViewTop])
                
                self.view.layoutIfNeeded()
            }
            
            if (self.captureSession?.isRunning == false) {
                DispatchQueue.global(qos: .background).async {
                    self.captureSession.startRunning()
                }
            }
        } else {
            let ac = UIAlertController(title: "Scanning not supported", message: "Your device does not support scanning a code from an item. Please use a device with a camera.", preferredStyle: .alert)
            ac.addAction(UIAlertAction(title: "Okay", style: .default))
            present(ac, animated: true)
        }
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
            
            if let actualCaptureSession = captureSession {
                actualCaptureSession.stopRunning()
            }
            
            UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseInOut) {
                
                self.toLabel.alpha = 1
                self.toView.alpha = 1
                self.pasteButton.alpha = 1
                self.amountView.alpha = 1
                self.amountLabel.alpha = 1
                self.availableAmount.alpha = 1
                self.availableButton.alpha = 1
                self.scannerView.alpha = 0
                self.nextLabel.text = "Next"
                
                NSLayoutConstraint.deactivate([self.nextViewTop])
                self.nextViewTop = NSLayoutConstraint(item: self.nextView, attribute: .top, relatedBy: .equal, toItem: self.availableAmount, attribute: .bottom, multiplier: 1, constant: 30)
                NSLayoutConstraint.activate([self.nextViewTop])
                
                self.setSendAllLabel()
                self.availableAmountTop.constant = 10
                self.availableButtonTop.constant = 0
                self.availableAmountCenterX.constant = 0
                self.questionCircle.alpha = 0
                
                self.view.layoutIfNeeded()
            }
        } else if self.nextLabel.text == "Manual input", self.onchainOrLightning == "lightning" {
            
            if let actualCaptureSession = captureSession {
                actualCaptureSession.stopRunning()
            }
            
            UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseInOut) {
                
                self.toLabel.alpha = 1
                self.toView.alpha = 1
                self.pasteButton.alpha = 1
                self.amountView.alpha = 0
                self.amountLabel.alpha = 0
                self.availableButton.alpha = 1
                self.scannerView.alpha = 0
                self.nextLabel.text = "Next"
                self.availableAmount.alpha = 1
                self.availableAmountTop.constant = -75
                self.availableButtonTop.constant = -85
                self.availableAmountCenterX.constant = -10
                self.questionCircle.alpha = 1
                
                if let actualMaxAmount = self.maximumSendableLNSats {
                    self.availableAmount.text = "You can send \(actualMaxAmount) satoshis."
                } else {
                    self.availableAmount.text = "You can send 0 satoshis."
                }
                
                NSLayoutConstraint.deactivate([self.nextViewTop])
                self.nextViewTop = NSLayoutConstraint(item: self.nextView, attribute: .top, relatedBy: .equal, toItem: self.availableAmount, attribute: .bottom, multiplier: 1, constant: 30)
                NSLayoutConstraint.activate([self.nextViewTop])
                
                self.view.layoutIfNeeded()
            }
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
            let alert = UIAlertController(title: "Check your connection", message: "You don't seem to be connected to the internet. Please try to connect.", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Okay", style: .cancel, handler: nil))
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
        
        self.invoiceLabel.text = nil
        self.toTextFieldHeight.constant = 0
        self.toTextField.text = nil
        self.amountTextField.text = nil
        self.toTextFieldTop.constant = 5
        self.invoiceLabelTop.constant = 10
        if let actualCaptureSession = captureSession {
            actualCaptureSession.stopRunning()
        }
        
        if sender.accessibilityIdentifier == "regular" {
            // Regular
            self.onchainOrLightning = "onchain"
            
            self.regularView.backgroundColor = UIColor(white: 1, alpha: 1)
            self.instantView.backgroundColor = UIColor(white: 1, alpha: 0.7)
            
            UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseInOut) {
                
                self.topLabel.text = "Send bitcoin from your bitcoin wallet to another bitcoin wallet. Scan a QR code or input manually."
                self.toLabel.text = "Address"
                self.toTextField.placeholder = "Enter address"
                
                self.toLabel.alpha = 1
                self.toView.alpha = 1
                self.pasteButton.alpha = 1
                self.amountView.alpha = 1
                self.amountLabel.alpha = 1
                self.availableAmount.alpha = 1
                self.availableButton.alpha = 1
                //self.nextView.alpha = 1
                self.scannerView.alpha = 0
                //self.nextViewTop.constant = -30
                self.nextLabel.text = "Next"
                
                NSLayoutConstraint.deactivate([self.nextViewTop])
                self.nextViewTop = NSLayoutConstraint(item: self.nextView, attribute: .top, relatedBy: .equal, toItem: self.availableAmount, attribute: .bottom, multiplier: 1, constant: 30)
                NSLayoutConstraint.activate([self.nextViewTop])
                
                self.setSendAllLabel()
                self.availableAmountTop.constant = 10
                self.availableButtonTop.constant = 0
                self.availableAmountCenterX.constant = 0
                self.questionCircle.alpha = 0
                
                self.view.layoutIfNeeded()
            }
        } else {
            // Instant
            self.onchainOrLightning = "lightning"
            
            self.regularView.backgroundColor = UIColor(white: 1, alpha: 0.7)
            self.instantView.backgroundColor = UIColor(white: 1, alpha: 1)
            
            UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseInOut) {
                
                self.topLabel.text = "Send bitcoin from your bitcoin lightning wallet to another bitcoin lightning wallet."
                self.toLabel.text = "Invoice"
                self.toTextField.placeholder = "Enter invoice"
                
                self.toLabel.alpha = 1
                self.toView.alpha = 1
                self.pasteButton.alpha = 1
                self.amountView.alpha = 0
                self.amountLabel.alpha = 0
                self.availableButton.alpha = 1
                self.scannerView.alpha = 0
                self.nextLabel.text = "Next"
                self.availableAmount.alpha = 1
                self.availableAmountTop.constant = -75
                self.availableButtonTop.constant = -85
                self.availableAmountCenterX.constant = -10
                self.questionCircle.alpha = 1
                
                if let actualMaxAmount = self.maximumSendableLNSats {
                    self.availableAmount.text = "You can send \(actualMaxAmount) satoshis."
                } else {
                    self.availableAmount.text = "You can send 0 satoshis."
                }
                
                NSLayoutConstraint.deactivate([self.nextViewTop])
                self.nextViewTop = NSLayoutConstraint(item: self.nextView, attribute: .top, relatedBy: .equal, toItem: self.availableAmount, attribute: .bottom, multiplier: 1, constant: 30)
                NSLayoutConstraint.activate([self.nextViewTop])
                
                self.view.layoutIfNeeded()
            }
        }
    }
    
    @IBAction func feeButtonTapped(_ sender: UIButton) {
        self.switchFeeSelection(tappedFee: sender.accessibilityIdentifier!)
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
