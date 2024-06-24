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

    @IBOutlet weak var downButton: UIButton!
    @IBOutlet weak var headerView: UIView!
    @IBOutlet weak var fromView: UIView!
    @IBOutlet weak var toView: UIView!
    @IBOutlet weak var amountView: UIView!
    @IBOutlet weak var nextView: UIView!
    
    @IBOutlet weak var fromButton: UIButton!
    @IBOutlet weak var fromLabel: UILabel!
    @IBOutlet weak var toTextField: UITextField!
    //@IBOutlet weak var toButton: UIButton!
    @IBOutlet weak var amountTextField: UITextField!
    @IBOutlet weak var availableAmount: UILabel!
    @IBOutlet weak var amountButton: UIButton!
    @IBOutlet weak var availableButton: UIButton!
    @IBOutlet weak var clipboardWidth: NSLayoutConstraint!
    @IBOutlet weak var toTextFieldTrailing: NSLayoutConstraint!
    @IBOutlet weak var pasteButton: UIButton!
    @IBOutlet weak var nextButton: UIButton!
    @IBOutlet weak var qrButton: UIButton!
    @IBOutlet weak var backgroundQR: UIView!
    @IBOutlet weak var backgroundPaste: UIView!
    @IBOutlet weak var backgroundKeyboard: UIView!
    @IBOutlet weak var keyboardButton: UIButton!
    @IBOutlet weak var toTextFieldHeight: NSLayoutConstraint!
    @IBOutlet weak var questionCircle: UIImageView!
    
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
    @IBOutlet weak var sendButton: UIButton!
    @IBOutlet weak var sendSpinner: UIActivityIndicatorView!
    @IBOutlet weak var sendLabel: UILabel!
    
    var btcAmount = 0.07255647
    var btclnAmount = 0.02266301
    var presetAmount:Double?
    var maximumSendableLNSats:Int?
    
    @IBOutlet weak var centerView: UIView!
    @IBOutlet weak var switchView: UIView!
    @IBOutlet weak var regularView: UIView!
    @IBOutlet weak var instantView: UIView!
    @IBOutlet weak var regularButton: UIButton!
    @IBOutlet weak var instantButton: UIButton!
    @IBOutlet weak var toLabel: UILabel!
    @IBOutlet weak var topLabel: UILabel!
    @IBOutlet weak var amountLabel: UILabel!
    @IBOutlet weak var nextLabel: UILabel!
    @IBOutlet weak var nextViewTop: NSLayoutConstraint!
    @IBOutlet weak var nextSpinner: UIActivityIndicatorView!
    @IBOutlet weak var qrImage: UIImageView!
    @IBOutlet weak var availableAmountTop: NSLayoutConstraint!
    @IBOutlet weak var availableAmountCenterX: NSLayoutConstraint!
    @IBOutlet weak var availableButtonTop: NSLayoutConstraint!
    @IBOutlet weak var invoiceLabel: UILabel!
    @IBOutlet weak var toTextFieldTop: NSLayoutConstraint! // 5
    @IBOutlet weak var invoiceLabelTop: NSLayoutConstraint! // 10
    
    var captureSession: AVCaptureSession!
    var previewLayer: AVCaptureVideoPreviewLayer!
    @IBOutlet weak var scannerView: UIView!
    var scannerWorks = false
    
    @IBOutlet weak var fastView: UIView!
    @IBOutlet weak var mediumView: UIView!
    @IBOutlet weak var slowView: UIView!
    @IBOutlet weak var fastButton: UIButton!
    @IBOutlet weak var mediumButton: UIButton!
    @IBOutlet weak var slowButton: UIButton!
    @IBOutlet weak var satsFast: UILabel!
    @IBOutlet weak var eurosFast: UILabel!
    @IBOutlet weak var satsMedium: UILabel!
    @IBOutlet weak var eurosMedium: UILabel!
    @IBOutlet weak var satsSlow: UILabel!
    @IBOutlet weak var eurosSlow: UILabel!
    
    // Confirm view
    @IBOutlet weak var yellowCard: UIView!
    @IBOutlet weak var confirmToCard: UIView!
    @IBOutlet weak var confirmAddressLabel: UILabel!
    @IBOutlet weak var confirmAmountCard: UIView!
    @IBOutlet weak var confirmAmountLabel: UILabel!
    @IBOutlet weak var confirmEuroLabel: UILabel!
    
    var feeLow:Float = 0.0
    var feeMedium:Float = 0.0
    var feeHigh:Float = 0.0
    var selectedFee = "medium"
    
    var eurValue = 0.0
    var chfValue = 0.0
    
    var onchainOrLightning = "onchain"
    var selectedInput = "qr"
    
    var completedTransaction:Transaction?
    
    var homeVC:HomeViewController?
    
    override func viewDidLoad() {
        super.viewDidLoad()

        downButton.setTitle("", for: .normal)
        fromButton.setTitle("", for: .normal)
        //toButton.setTitle("", for: .normal)
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
        
        headerView.layer.cornerRadius = 13
        fromView.layer.cornerRadius = 13
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
        
        yellowCard.layer.shadowColor = UIColor.black.cgColor
        yellowCard.layer.shadowOffset = CGSize(width: 0, height: 7)
        yellowCard.layer.shadowRadius = 10.0
        yellowCard.layer.shadowOpacity = 0.1
        
        fastView.layer.cornerRadius = 13
        mediumView.layer.cornerRadius = 13
        slowView.layer.cornerRadius = 13
        
        fastView.layer.shadowColor = UIColor.black.cgColor
        fastView.layer.shadowOffset = CGSize(width: 0, height: 7)
        fastView.layer.shadowRadius = 10.0
        fastView.layer.shadowOpacity = 0.1
        
        mediumView.layer.shadowColor = UIColor.black.cgColor
        mediumView.layer.shadowOffset = CGSize(width: 0, height: 7)
        mediumView.layer.shadowRadius = 10.0
        mediumView.layer.shadowOpacity = 0.1
        
        slowView.layer.shadowColor = UIColor.black.cgColor
        slowView.layer.shadowOffset = CGSize(width: 0, height: 7)
        slowView.layer.shadowRadius = 10.0
        slowView.layer.shadowOpacity = 0.1
        
        backgroundQR.layer.cornerRadius = 13
        backgroundPaste.layer.cornerRadius = 13
        backgroundKeyboard.layer.cornerRadius = 13
        
        backgroundQR.layer.shadowColor = UIColor.black.cgColor
        backgroundQR.layer.shadowOffset = CGSize(width: 0, height: 7)
        backgroundQR.layer.shadowRadius = 10.0
        backgroundQR.layer.shadowOpacity = 0.1
        
        backgroundPaste.layer.shadowColor = UIColor.black.cgColor
        backgroundPaste.layer.shadowOffset = CGSize(width: 0, height: 7)
        backgroundPaste.layer.shadowRadius = 10.0
        backgroundPaste.layer.shadowOpacity = 0.1
        
        backgroundKeyboard.layer.shadowColor = UIColor.black.cgColor
        backgroundKeyboard.layer.shadowOffset = CGSize(width: 0, height: 7)
        backgroundKeyboard.layer.shadowRadius = 10.0
        backgroundKeyboard.layer.shadowOpacity = 0.1
        
        toTextField.delegate = self
        amountTextField.delegate = self
        amountTextField.addDoneButton(target: self, returnaction: #selector(self.doneButtonTapped))
        
        let numberFormatter = NumberFormatter()
        numberFormatter.numberStyle = .decimal
        self.availableAmount.text = "Send all: \(numberFormatter.number(from: "\(self.btcAmount)".replacingOccurrences(of: ".", with: Locale.current.decimalSeparator!).replacingOccurrences(of: ",", with: Locale.current.decimalSeparator!))!.decimalValue as NSNumber)".replacingOccurrences(of: "00000000001", with: "").replacingOccurrences(of: "99999999999", with: "").replacingOccurrences(of: "0000000001", with: "").replacingOccurrences(of: "9999999999", with: "")
        
    }
    
    
    func fixQrScanner() -> Bool {
        
        captureSession = AVCaptureSession()
        guard let videoCaptureDevice = AVCaptureDevice.default(for: .video) else {
            self.scannerWorks = false
            return false
        }
        let videoInput: AVCaptureDeviceInput
        do {
            videoInput = try AVCaptureDeviceInput(device: videoCaptureDevice)
        } catch {
            self.scannerWorks = false
            return false
        }
        
        if (captureSession.canAddInput(videoInput)) {
            captureSession.addInput(videoInput)
        } else {
            //failed()
            return false
        }
        
        let metadataOutput = AVCaptureMetadataOutput()
        
        if (captureSession.canAddOutput(metadataOutput)) {
            captureSession.addOutput(metadataOutput)

            metadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
            metadataOutput.metadataObjectTypes = [.qr]
        } else {
            //failed()
            return false
        }
        
        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.frame = self.scannerView.layer.bounds
        previewLayer.videoGravity = .resizeAspectFill
        self.scannerView.layer.addSublayer(previewLayer)
        
        //captureSession.startRunning()
        self.scannerWorks = true
        return true
    }
    
    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        
        if let actualCaptureSession = captureSession {
            actualCaptureSession.stopRunning()
        }

        if let metadataObject = metadataObjects.first {
            guard let readableObject = metadataObject as? AVMetadataMachineReadableCodeObject else { return }
            guard let stringValue = readableObject.stringValue else { return }
            AudioServicesPlaySystemSound(SystemSoundID(kSystemSoundID_Vibrate))
            found(code: stringValue)
        }
    }
    
    func found(code: String) {
        
        print("Code: " + code)
        
        // Check bitcoin or lightning in code to switch view if needed.
        var addressType = "onchain"
        if code.lowercased().contains("bitcoin") && code.lowercased().contains("ln") {
            addressType = ""
        } else if code.lowercased().contains("ln") || code.contains("lightning") {
            addressType = "lightning"
        } else if !code.contains("bitcoin") && !code.lowercased().contains("ln") {
            addressType = ""
        }
        
        if !code.contains("bitcoin") && !code.lowercased().contains("ln") {
             // No valid address.
             self.toTextField.text = nil
             self.amountTextField.text = nil
             let ac = UIAlertController(title: "No address found.", message: "Please scan a bitcoin or lightning address QR code or input the address manually.", preferredStyle: .alert)
             ac.addAction(UIAlertAction(title: "Okay", style: .default))
             present(ac, animated: true)
         } else {
             
            let address = code.lowercased().replacingOccurrences(of: "bitcoin:", with: "").replacingOccurrences(of: "lightning:", with: "")
            let components = address.components(separatedBy: "?")
            if let bitcoinAddress = components.first {
                // Success.
                self.toTextField.alpha = 0
                self.invoiceLabel.text = bitcoinAddress
                self.invoiceLabel.alpha = 1
                self.invoiceLabelTop.constant = 20
                
                if components.count > 1 {
                    if components[1].contains("amount") {
                        //let bitcoinAmount = components[1].replacingOccurrences(of: "amount=", with: "")
                        
                        let amountString = components[1].components(separatedBy: "&")
                        
                        let numberFormatter = NumberFormatter()
                        numberFormatter.numberStyle = .decimal
                        let bitcoinAmount = (numberFormatter.number(from: amountString[0].replacingOccurrences(of: "amount=", with: "").replacingOccurrences(of: ".", with: Locale.current.decimalSeparator!).replacingOccurrences(of: ",", with: Locale.current.decimalSeparator!)) ?? 0).decimalValue as NSNumber
                        
                        self.amountTextField.text = "\(bitcoinAmount)"
                    } else {
                        self.amountTextField.text = nil
                    }
                } else {
                    self.amountTextField.text = nil
                }
            } else {
                self.toTextField.text = nil
                self.amountTextField.text = nil
                let ac = UIAlertController(title: "No bitcoin address found.", message: "Please scan a bitcoin address QR code or input the address manually.", preferredStyle: .alert)
                ac.addAction(UIAlertAction(title: "Okay", style: .default))
                present(ac, animated: true)
            }
        }
        
        UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseInOut) {
            
            self.scannerView.alpha = 0
            self.toLabel.alpha = 1
            self.toView.alpha = 1
            
            if addressType == "onchain" {
                
                self.onchainOrLightning = "onchain"
                self.regularView.backgroundColor = UIColor(white: 1, alpha: 1)
                self.instantView.backgroundColor = UIColor(white: 1, alpha: 0.7)
                self.topLabel.text = "Send bitcoin from your bitcoin wallet to another bitcoin wallet. Scan a QR code or input manually."
                self.toLabel.text = "Address"
                self.toTextField.placeholder = "Enter address"
                
                self.pasteButton.alpha = 1
                self.qrImage.alpha = 1
                self.toTextFieldTrailing.constant = -10
                self.amountLabel.alpha = 1
                self.amountView.alpha = 1
                self.availableAmount.alpha = 1
                self.availableButton.alpha = 1
                self.nextLabel.text = "Next"
                //self.nextViewTop.constant = -30
                
                NSLayoutConstraint.deactivate([self.nextViewTop])
                self.nextViewTop = NSLayoutConstraint(item: self.nextView, attribute: .top, relatedBy: .equal, toItem: self.availableAmount, attribute: .bottom, multiplier: 1, constant: 30)
                NSLayoutConstraint.activate([self.nextViewTop])
                
                let numberFormatter = NumberFormatter()
                numberFormatter.numberStyle = .decimal
                self.availableAmount.text = "Send all: \(numberFormatter.number(from: "\(self.btcAmount)".replacingOccurrences(of: ".", with: Locale.current.decimalSeparator!).replacingOccurrences(of: ",", with: Locale.current.decimalSeparator!))!.decimalValue as NSNumber)".replacingOccurrences(of: "00000000001", with: "").replacingOccurrences(of: "99999999999", with: "").replacingOccurrences(of: "0000000001", with: "").replacingOccurrences(of: "9999999999", with: "")
                self.availableAmountTop.constant = 10
                self.availableButtonTop.constant = 0
                self.availableAmountCenterX.constant = 0
                self.questionCircle.alpha = 0
                
            } else if addressType == "lightning" {
                
                self.onchainOrLightning = "lightning"
                self.regularView.backgroundColor = UIColor(white: 1, alpha: 0.7)
                self.instantView.backgroundColor = UIColor(white: 1, alpha: 1)
                self.topLabel.text = "Send bitcoin from your bitcoin lightning wallet to another bitcoin lightning wallet."
                self.toLabel.text = "Invoice"
                self.toTextField.placeholder = "Enter invoice"
                
                self.pasteButton.alpha = 1
                self.qrImage.alpha = 1
                self.toTextFieldTrailing.constant = -10
                self.amountView.alpha = 0
                self.amountLabel.alpha = 0
                self.availableAmount.alpha = 1
                self.availableButton.alpha = 1
                self.nextLabel.text = "Next"
                self.nextViewTop.constant = -120
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
            } else if addressType == "" && self.onchainOrLightning == "onchain" {
                
                self.pasteButton.alpha = 1
                self.qrImage.alpha = 1
                self.toTextFieldTrailing.constant = -10
                self.amountLabel.alpha = 1
                self.amountView.alpha = 1
                self.availableAmount.alpha = 1
                self.availableButton.alpha = 1
                self.nextLabel.text = "Next"
                //self.nextViewTop.constant = -30
                
                NSLayoutConstraint.deactivate([self.nextViewTop])
                self.nextViewTop = NSLayoutConstraint(item: self.nextView, attribute: .top, relatedBy: .equal, toItem: self.availableAmount, attribute: .bottom, multiplier: 1, constant: 30)
                NSLayoutConstraint.activate([self.nextViewTop])
                
                let numberFormatter = NumberFormatter()
                numberFormatter.numberStyle = .decimal
                self.availableAmount.text = "Send all: \(numberFormatter.number(from: "\(self.btcAmount)".replacingOccurrences(of: ".", with: Locale.current.decimalSeparator!).replacingOccurrences(of: ",", with: Locale.current.decimalSeparator!))!.decimalValue as NSNumber)".replacingOccurrences(of: "00000000001", with: "").replacingOccurrences(of: "99999999999", with: "").replacingOccurrences(of: "0000000001", with: "").replacingOccurrences(of: "9999999999", with: "")
                self.availableAmountTop.constant = 10
                self.availableButtonTop.constant = 0
                self.availableAmountCenterX.constant = 0
                self.questionCircle.alpha = 0
            } else if addressType == "" && self.onchainOrLightning == "lightning" {
                
                self.pasteButton.alpha = 1
                self.qrImage.alpha = 1
                self.toTextFieldTrailing.constant = -10
                self.amountView.alpha = 0
                self.amountLabel.alpha = 0
                self.availableAmount.alpha = 1
                self.availableButton.alpha = 1
                self.nextLabel.text = "Next"
                self.nextViewTop.constant = -120
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
            }
            
            self.view.layoutIfNeeded()
        }
    }
    
    
    override func viewWillAppear(_ animated: Bool) {
        
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillDisappear), name: UIResponder.keyboardWillHideNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillAppear), name: UIResponder.keyboardWillShowNotification, object: nil)
        
        if (captureSession?.isRunning == false) {
            captureSession.startRunning()
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        
        if (captureSession?.isRunning == true) {
            captureSession.stopRunning()
        }
    }
    
    @objc func keyboardWillDisappear() {
        
        //self.toButton.alpha = 1
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
    
    @IBAction func fromButtonTapped(_ sender: UIButton) {
        
        let numberFormatter = NumberFormatter()
        numberFormatter.numberStyle = .decimal
        
        let actionSheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        let btcOption = UIAlertAction(title: "My BTC wallet", style: .default) { (action) in
            self.fromLabel.text = "My BTC wallet"
            self.toTextField.text = ""
            self.availableAmount.text = "Send all: \(numberFormatter.number(from: "\(self.btcAmount)")!.decimalValue as NSNumber)".replacingOccurrences(of: "00000000001", with: "").replacingOccurrences(of: "99999999999", with: "").replacingOccurrences(of: "0000000001", with: "").replacingOccurrences(of: "9999999999", with: "")
            self.clipboardWidth.constant = 20
            self.toTextFieldTrailing.constant = -10
        }
        let btclnOption = UIAlertAction(title: "My BTCLN wallet", style: .default) { (action) in
            
            let alert = UIAlertController(title: "Unavailable", message: "This feature is still being worked on.", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Okay", style: .cancel, handler: nil))
            self.present(alert, animated: true)
            
            return
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
    
    /*@IBAction func toButtonTapped(_ sender: UIButton) {
        
        if toTextField.text != "My BTC wallet" {
            self.toTextField.becomeFirstResponder()
            //self.toButton.alpha = 0
        }
    }*/
    
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
                self.qrImage.alpha = 0
                self.toTextFieldTrailing.constant = -10
                self.amountView.alpha = 0
                self.amountLabel.alpha = 0
                self.availableAmount.alpha = 0
                self.availableButton.alpha = 0
                //self.nextView.alpha = 0
                self.scannerView.alpha = 1
                self.nextLabel.text = "Manual input"
                
                NSLayoutConstraint.deactivate([self.nextViewTop])
                self.nextViewTop = NSLayoutConstraint(item: self.nextView, attribute: .top, relatedBy: .equal, toItem: self.scannerView, attribute: .bottom, multiplier: 1, constant: 30)
                NSLayoutConstraint.activate([self.nextViewTop])
                
                self.view.layoutIfNeeded()
            }
            
            if (self.captureSession?.isRunning == false) {
                self.captureSession.startRunning()
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
            
            if !Reachability.isConnectedToNetwork() {
                // User not connected to internet.
                let alert = UIAlertController(title: "Check your connection", message: "You don't seem to be connected to the internet. Please try to connect.", preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "Okay", style: .cancel, handler: nil))
                self.present(alert, animated: true)
                return
            }
            
            var invoiceText = self.toTextField.text
            if self.selectedInput != "keyboard" {
                invoiceText = self.invoiceLabel.text
            }
            
            let formatter = NumberFormatter()
            formatter.decimalSeparator = "."
            if invoiceText == nil || invoiceText?.trimmingCharacters(in: .whitespaces) == "" || self.amountTextField.text == nil || self.amountTextField.text?.trimmingCharacters(in: .whitespacesAndNewlines) == "" || CGFloat(truncating: formatter.number(from: self.amountTextField.text?.replacingOccurrences(of: ",", with: ".") ?? "0.0")!) == 0  {
                
                // Fields are left empty or the amount if set to zero.
                
            } else if CGFloat(truncating: formatter.number(from: self.amountTextField.text?.replacingOccurrences(of: ",", with: ".") ?? "0.0")!) > self.btcAmount {
                
                // Insufficient funds available.
                let alert = UIAlertController(title: "Oops!", message: "Make sure the amount of BTC you wish to send is within your spendable balance.", preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "Okay", style: .cancel, handler: nil))
                self.present(alert, animated: true)
            } else {
            
                self.nextLabel.alpha = 0
                self.nextSpinner.startAnimating()
                
                var currencySymbol = "€"
                var conversionRate:CGFloat = 0
                var eurAmount = CacheManager.getCachedData(key: "eurvalue") as? CGFloat
                var chfAmount = CacheManager.getCachedData(key: "chfvalue") as? CGFloat
                conversionRate = eurAmount ?? 0.0
                if UserDefaults.standard.value(forKey: "currency") as? String == "CHF" {
                    currencySymbol = "CHF"
                    conversionRate = chfAmount ?? 0.0
                }
                let labelActualAmount = CGFloat(truncating: NumberFormatter().number(from: ((self.amountTextField.text ?? "0").replacingOccurrences(of: ".", with: Locale.current.decimalSeparator!).replacingOccurrences(of: ",", with: Locale.current.decimalSeparator!)))!)
                
                self.confirmAddressLabel.text = invoiceText
                self.confirmAmountLabel.text = "\(self.amountTextField.text ?? "0") btc"
                self.confirmEuroLabel.text = "\(Int(labelActualAmount*conversionRate)) \(currencySymbol)"
                
                self.fromConfirmation.text = self.fromLabel.text
                self.toConfirmation.text = invoiceText
                self.amountConfirmation.text = self.amountTextField.text
                
                if let actualBlockchain = LightningNodeService.shared.getBlockchain(), let actualWallet = LightningNodeService.shared.getWallet() {
                    
                    let actualAddress:String = self.toConfirmation.text!
                    let actualAmount:Int = Int((CGFloat(truncating: NumberFormatter().number(from: ((self.amountConfirmation.text!).replacingOccurrences(of: ".", with: Locale.current.decimalSeparator!).replacingOccurrences(of: ",", with: Locale.current.decimalSeparator!)))!)*100000000).rounded())
                    
                    Task {
                        do {
                            let high = try actualBlockchain.estimateFee(target: 1)
                            let medium = try actualBlockchain.estimateFee(target: 3)
                            let low = try actualBlockchain.estimateFee(target: 6)
                            
                            print("High: \(high.asSatPerVb()), Medium: \(medium.asSatPerVb()), Low: \(low.asSatPerVb())")
                            
                            self.feeLow = Float(Int(low.asSatPerVb()*10))/10
                            self.feeMedium = Float(Int(medium.asSatPerVb()*10))/10
                            self.feeHigh = Float(Int(high.asSatPerVb()*10))/10
                            
                            print("Adjusted - High: \(self.feeHigh), Medium: \(self.feeMedium), Low: \(self.feeLow)")
                            
                            // TODO: Add fee rate to different transactions? .feeRate vs .feeAbsolute
                            var address = try Address(address: actualAddress, network: .bitcoin)
                            if UserDefaults.standard.value(forKey: "envkey") as? Int == 0 {
                                address = try Address(address: actualAddress, network: .testnet)
                            }
                            let script = address.scriptPubkey()
                            let txBuilder = TxBuilder().addRecipient(script: script, amount: UInt64(actualAmount))
                            let details = try txBuilder.finish(wallet: actualWallet)
                            let _ = try actualWallet.sign(psbt: details.psbt, signOptions: nil)
                            let tx = details.psbt.extractTx()
                            let size = tx.vsize()

                            print("Size: \(String(describing: size))")
                            print("High: \(self.feeHigh*Float(size)), Medium: \(self.feeMedium*Float(size)), Low: \(self.feeLow*Float(size))")
                            
                            self.satsFast.text = "\(Int(self.feeHigh*Float(size))) sats"
                            self.satsMedium.text = "\(Int(self.feeMedium*Float(size))) sats"
                            self.satsSlow.text = "\(Int(self.feeLow*Float(size))) sats"
                            
                            let fast1 = CGFloat(self.feeHigh*Float(size))
                            var fastText = "\(CGFloat(Int(((fast1/100000000)*conversionRate)*100))/100)"
                            if fastText.count == 3 {
                                fastText = fastText + "0"
                            }
                            let medium1 = CGFloat(self.feeMedium*Float(size))
                            var mediumText = "\(CGFloat(Int(((medium1/100000000)*conversionRate)*100))/100)"
                            if mediumText.count == 3 {
                                mediumText = mediumText + "0"
                            }
                            let slow1 = CGFloat(self.feeLow*Float(size))
                            var slowText = "\(CGFloat(Int(((slow1/100000000)*conversionRate)*100))/100)"
                            if slowText.count == 3 {
                                slowText = slowText + "0"
                            }
                            
                            self.eurosFast.text = fastText + " " + currencySymbol
                            self.eurosMedium.text = mediumText + " " + currencySymbol
                            self.eurosSlow.text = slowText + " " + currencySymbol
                            
                            
                            DispatchQueue.main.async {
                                UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseInOut) {
                                    
                                    NSLayoutConstraint.deactivate([self.scrollViewTrailing])
                                    self.scrollViewTrailing = NSLayoutConstraint(item: self.scrollView, attribute: .trailing, relatedBy: .equal, toItem: self.view, attribute: .leading, multiplier: 1, constant: 0)
                                    NSLayoutConstraint.activate([self.scrollViewTrailing])
                                    self.view.layoutIfNeeded()
                                }
                                
                                self.nextLabel.alpha = 1
                                self.nextSpinner.stopAnimating()
                            }
                        } catch let error as BdkError {
                            
                            print("BDK error: \(error)")
                            DispatchQueue.main.async {
                                
                                self.nextLabel.alpha = 1
                                self.nextSpinner.stopAnimating()
                                
                                let alert = UIAlertController(title: "Oops!", message: "We couldn't proceed to the next step. Error: \(error).", preferredStyle: .alert)
                                alert.addAction(UIAlertAction(title: "Okay", style: .default))
                                self.present(alert, animated: true)
                                
                                SentrySDK.capture(error: error)
                            }
                        } catch {
                            print("Error: \(error.localizedDescription)")
                            DispatchQueue.main.async {
                                self.nextLabel.alpha = 1
                                self.nextSpinner.stopAnimating()
                                
                                let alert = UIAlertController(title: "Oops!", message: "We couldn't proceed to the next step. Error: \(error.localizedDescription).", preferredStyle: .alert)
                                alert.addAction(UIAlertAction(title: "Okay", style: .default))
                                self.present(alert, animated: true)
                                
                                SentrySDK.capture(error: error)
                            }
                        }
                    }
                }
            }
        } else if self.nextLabel.text == "Next" && self.onchainOrLightning == "lightning" {
            
            if !Reachability.isConnectedToNetwork() {
                // User not connected to internet.
                let alert = UIAlertController(title: "Check your connection", message: "You don't seem to be connected to the internet. Please try to connect.", preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "Okay", style: .cancel, handler: nil))
                self.present(alert, animated: true)
                return
            }
            
            var invoiceText = self.toTextField.text
            if self.selectedInput != "keyboard" {
                invoiceText = self.invoiceLabel.text
            }
            
            // Pay lightning invoice.
            if invoiceText == nil || invoiceText?.trimmingCharacters(in: .whitespacesAndNewlines) == "" {
                // Invoice field was left empty.
            } else {
                
                if let parsedInvoice = Bindings.Bolt11Invoice.fromStr(s: invoiceText!).getValue() {
                    if let invoiceAmountMilli = parsedInvoice.amountMilliSatoshis() {
                        let invoiceAmount = Int(invoiceAmountMilli)/1000
                        
                        var correctValue:CGFloat = self.eurValue
                        var currencySymbol = "€"
                        if UserDefaults.standard.value(forKey: "currency") as? String == "CHF" {
                            correctValue = self.chfValue
                            currencySymbol = "CHF"
                        }
                        
                        var transactionValue = CGFloat(invoiceAmount)/100000000
                        var convertedValue = String(CGFloat(Int(transactionValue*correctValue*100))/100)
                        
                        let alert = UIAlertController(title: "Send transaction", message: "Are you sure you want to pay \(invoiceAmount) satoshis (\(currencySymbol) \(convertedValue)) for this invoice?", preferredStyle: .alert)
                        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
                        alert.addAction(UIAlertAction(title: "Confirm", style: .default, handler: {_ in
                            
                            self.nextLabel.alpha = 0
                            self.nextSpinner.startAnimating()
                            
                            Task {
                                do {
                                    let paymentHash = try await LightningNodeService.shared.sendPayment(invoice: String(invoiceText!.replacingOccurrences(of: " ", with: "")))
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                                        
                                        if let thisPayment = LightningNodeService.shared.getPaymentDetails(paymentHash: paymentHash) {
                                            
                                            if thisPayment.status != .failed {
                                                // Success alert
                                                let alert = UIAlertController(title: "Payment successful", message: "Payment hash: \(paymentHash)", preferredStyle: .alert)
                                                alert.addAction(UIAlertAction(title: "Okay", style: .default, handler: { _ in
                                                    
                                                    if let thisPayment = LightningNodeService.shared.getPaymentDetails(paymentHash: paymentHash) {
                                                        
                                                        let newTransaction = Transaction()
                                                        newTransaction.id = thisPayment.preimage ?? paymentHash
                                                        newTransaction.sent = Int(thisPayment.amountMsat ?? 0)/1000
                                                        newTransaction.received = 0
                                                        newTransaction.isLightning = true
                                                        newTransaction.timestamp = Int(Date().timeIntervalSince1970)
                                                        newTransaction.confirmations = 0
                                                        newTransaction.height = 0
                                                        newTransaction.fee = 0
                                                        newTransaction.isBittr = false
                                                        
                                                        self.completedTransaction = newTransaction
                                                        
                                                        if let actualHomeVC = self.homeVC {
                                                            actualHomeVC.setTransactions += [newTransaction]
                                                            actualHomeVC.setTransactions.sort { transaction1, transaction2 in
                                                                transaction1.timestamp > transaction2.timestamp
                                                            }
                                                            actualHomeVC.homeTableView.reloadData()
                                                        }
                                                        
                                                        self.performSegue(withIdentifier: "SendToTransaction", sender: self)
                                                    }
                                                }))
                                                self.present(alert, animated: true)
                                            } else {
                                                // Payment came back failed.
                                                let alert = UIAlertController(title: "Payment failed", message: "We were able to broadcast your payment, but it failed.\n\nIf funds were recently deposited into your Lightning wallet, it may take some time for these to be confirmed and available for sending elsewhere.", preferredStyle: .alert)
                                                alert.addAction(UIAlertAction(title: "Okay", style: .default))
                                                self.present(alert, animated: true)
                                            }
                                        } else {
                                            // Success alert
                                            let alert = UIAlertController(title: "Payment successful", message: "Payment hash: \(paymentHash)", preferredStyle: .alert)
                                            alert.addAction(UIAlertAction(title: "Okay", style: .default))
                                            self.present(alert, animated: true)
                                        }
                                        
                                        self.nextLabel.alpha = 1
                                        self.nextSpinner.stopAnimating()
                                        self.toTextField.text = nil
                                        
                                        self.invoiceLabel.text = nil
                                        self.toTextFieldHeight.constant = 0
                                        self.toTextField.text = nil
                                        self.amountTextField.text = nil
                                        self.toTextFieldTop.constant = 5
                                        self.invoiceLabelTop.constant = 10
                                    }
                                } catch let error as NodeError {
                                    let errorString = handleNodeError(error)
                                    DispatchQueue.main.async {
                                        // Error alert for NodeError
                                        
                                        self.nextLabel.alpha = 1
                                        self.nextSpinner.stopAnimating()
                                        
                                        let alert = UIAlertController(title: "Payment Error", message: errorString.detail, preferredStyle: .alert)
                                        alert.addAction(UIAlertAction(title: "Okay", style: .default))
                                        self.present(alert, animated: true)
                                        
                                        SentrySDK.capture(error: error)
                                    }
                                } catch {
                                    DispatchQueue.main.async {
                                        // General error alert
                                        
                                        self.nextLabel.alpha = 1
                                        self.nextSpinner.stopAnimating()
                                        
                                        let alert = UIAlertController(title: "Unexpected Error", message: error.localizedDescription, preferredStyle: .alert)
                                        alert.addAction(UIAlertAction(title: "Okay", style: .default))
                                        self.present(alert, animated: true)
                                        
                                        SentrySDK.capture(error: error)
                                    }
                                }
                            }
                        }))
                        self.present(alert, animated: true)
                    }
                }
            }
        } else if self.nextLabel.text == "Manual input", self.onchainOrLightning == "onchain" {
            
            if let actualCaptureSession = captureSession {
                actualCaptureSession.stopRunning()
            }
            
            UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseInOut) {
                
                self.toLabel.alpha = 1
                self.toView.alpha = 1
                self.pasteButton.alpha = 1
                self.qrImage.alpha = 1
                self.toTextFieldTrailing.constant = -10
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
                
                let numberFormatter = NumberFormatter()
                numberFormatter.numberStyle = .decimal
                self.availableAmount.text = "Send all: \(numberFormatter.number(from: "\(self.btcAmount)".replacingOccurrences(of: ".", with: Locale.current.decimalSeparator!).replacingOccurrences(of: ",", with: Locale.current.decimalSeparator!))!.decimalValue as NSNumber)".replacingOccurrences(of: "00000000001", with: "").replacingOccurrences(of: "99999999999", with: "").replacingOccurrences(of: "0000000001", with: "").replacingOccurrences(of: "9999999999", with: "")
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
                self.qrImage.alpha = 1
                //self.toTextFieldTrailing.constant = -10
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
        
        UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseInOut) {
            
            NSLayoutConstraint.deactivate([self.scrollViewTrailing])
            self.scrollViewTrailing = NSLayoutConstraint(item: self.scrollView, attribute: .trailing, relatedBy: .equal, toItem: self.view, attribute: .trailing, multiplier: 1, constant: 0)
            NSLayoutConstraint.activate([self.scrollViewTrailing])
            self.view.layoutIfNeeded()
        }
    }
    
    @IBAction func sendButtonTapped(_ sender: UIButton) {
        
        if !Reachability.isConnectedToNetwork() {
            // User not connected to internet.
            let alert = UIAlertController(title: "Check your connection", message: "You don't seem to be connected to the internet. Please try to connect.", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Okay", style: .cancel, handler: nil))
            self.present(alert, animated: true)
            return
        }
        
        var feeSatoshis = (self.satsMedium.text ?? "no").replacingOccurrences(of: " sats", with: "")
        if self.selectedFee == "low" {
            feeSatoshis = (self.satsSlow.text ?? "no").replacingOccurrences(of: " sats", with: "")
        } else if self.selectedFee == "high" {
            feeSatoshis = (self.satsFast.text ?? "no").replacingOccurrences(of: " sats", with: "")
        }
        
        let alert = UIAlertController(title: "Send transaction", message: "Are you sure you want to send \(self.amountConfirmation.text ?? "these") btc, with a fee of \(feeSatoshis) satoshis, to \(self.toConfirmation.text ?? "this address")?", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        alert.addAction(UIAlertAction(title: "Confirm", style: .default, handler: {_ in 
            
            self.sendLabel.alpha = 0
            self.sendSpinner.startAnimating()
            
            if let actualWallet = LightningNodeService.shared.getWallet(), let actualBlockchain = LightningNodeService.shared.getBlockchain() {
                
                let actualAmount:Int = Int((CGFloat(truncating: NumberFormatter().number(from: ((self.amountConfirmation.text!).replacingOccurrences(of: ".", with: Locale.current.decimalSeparator!).replacingOccurrences(of: ",", with: Locale.current.decimalSeparator!)))!)*100000000).rounded())
                
                // tb1qw2c3lxufxqe2x9s4rdzh65tpf4d7fssjgh8nv6
                let actualAddress:String = self.toConfirmation.text!
                
                Task {
                    do {
                        var address = try Address(address: actualAddress, network: .bitcoin)
                        if UserDefaults.standard.value(forKey: "envkey") as? Int == 0 {
                            address = try Address(address: actualAddress, network: .testnet)
                        }
                        let script = address.scriptPubkey()
                        var selectedVbyte:Float = self.feeMedium
                        if self.selectedFee == "low" {
                            selectedVbyte = self.feeLow
                        } else if self.selectedFee == "high" {
                            selectedVbyte = self.feeHigh
                        }
                        let txBuilder = TxBuilder().addRecipient(script: script, amount: UInt64(actualAmount)).feeRate(satPerVbyte: selectedVbyte)
                        let details = try txBuilder.finish(wallet: actualWallet)
                        let _ = try actualWallet.sign(psbt: details.psbt, signOptions: nil)
                        let tx = details.psbt.extractTx()
                        try actualBlockchain.broadcast(transaction: tx)
                        let txid = details.psbt.txid()
                        print("Transaction ID: \(txid)")
                        
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            print("Successful transaction.")
                            self.sendLabel.alpha = 1
                            self.sendSpinner.stopAnimating()
                            
                            let successAlert = UIAlertController(title: "Success", message: "Your transaction has been sent and will show up in your wallet shortly.", preferredStyle: .alert)
                            successAlert.addAction(UIAlertAction(title: "Okay", style: .default, handler: {_ in
                                
                                let newTransaction = Transaction()
                                newTransaction.id = "\(txid)"
                                newTransaction.confirmations = 0
                                newTransaction.timestamp = Int(Date().timeIntervalSince1970)
                                newTransaction.height = 0
                                newTransaction.received = 0
                                var satsLabel = self.satsMedium
                                if self.selectedFee == "low" {
                                    satsLabel = self.satsSlow
                                } else if self.selectedFee == "high" {
                                    satsLabel = self.satsFast
                                }
                                newTransaction.fee = Int(CGFloat(truncating: NumberFormatter().number(from: satsLabel!.text!.replacingOccurrences(of: " sats", with: "").replacingOccurrences(of: ".", with: Locale.current.decimalSeparator!).replacingOccurrences(of: ",", with: Locale.current.decimalSeparator!))!))
                                newTransaction.sent = actualAmount + newTransaction.fee
                                newTransaction.isLightning = false
                                newTransaction.isBittr = false
                                
                                self.completedTransaction = newTransaction
                                
                                if let actualHomeVC = self.homeVC {
                                    actualHomeVC.setTransactions += [newTransaction]
                                    actualHomeVC.setTransactions.sort { transaction1, transaction2 in
                                        transaction1.timestamp > transaction2.timestamp
                                    }
                                    actualHomeVC.homeTableView.reloadData()
                                }
                                
                                self.performSegue(withIdentifier: "SendToTransaction", sender: self)
                                
                                self.invoiceLabel.text = nil
                                self.toTextFieldHeight.constant = 0
                                self.toTextField.text = nil
                                self.amountTextField.text = nil
                                self.toTextFieldTop.constant = 5
                                self.invoiceLabelTop.constant = 10
                                UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseInOut) {
                                    NSLayoutConstraint.deactivate([self.scrollViewTrailing])
                                    self.scrollViewTrailing = NSLayoutConstraint(item: self.scrollView, attribute: .trailing, relatedBy: .equal, toItem: self.view, attribute: .trailing, multiplier: 1, constant: 0)
                                    NSLayoutConstraint.activate([self.scrollViewTrailing])
                                    self.view.layoutIfNeeded()
                                }
                            }))
                            self.present(successAlert, animated: true)
                        }
                    } catch {
                        print("Transaction error: \(error.localizedDescription)")
                        DispatchQueue.main.async {
                            SentrySDK.capture(error: error)
                            let alert = UIAlertController(title: "Error", message: "We're unable to complete your transaction. We're receiving the following error message: \(error.localizedDescription).", preferredStyle: .alert)
                            alert.addAction(UIAlertAction(title: "Okay", style: .cancel, handler: nil))
                            self.present(alert, animated: true)
                        }
                    }
                }
            } else {
                print("Wallet or Blockchain instance not available.")
                DispatchQueue.main.async {
                    let alert = UIAlertController(title: "Error", message: "We're unable to complete your transaction. Please close and reopen our app and try again.", preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: "Okay", style: .cancel, handler: nil))
                    self.present(alert, animated: true)
                }
            }
        }))
        self.present(alert, animated: true)
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
                self.qrImage.alpha = 1
                self.toTextFieldTrailing.constant = -10
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
                
                let numberFormatter = NumberFormatter()
                numberFormatter.numberStyle = .decimal
                self.availableAmount.text = "Send all: \(numberFormatter.number(from: "\(self.btcAmount)".replacingOccurrences(of: ".", with: Locale.current.decimalSeparator!).replacingOccurrences(of: ",", with: Locale.current.decimalSeparator!))!.decimalValue as NSNumber)".replacingOccurrences(of: "00000000001", with: "").replacingOccurrences(of: "99999999999", with: "").replacingOccurrences(of: "0000000001", with: "").replacingOccurrences(of: "9999999999", with: "")
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
                self.qrImage.alpha = 1
                //self.toTextFieldTrailing.constant = -10
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
        
        switch sender.accessibilityIdentifier! {
        case "fast":
            self.fastView.backgroundColor = UIColor(white: 1, alpha: 1)
            self.mediumView.backgroundColor = UIColor(white: 1, alpha: 0.7)
            self.slowView.backgroundColor = UIColor(white: 1, alpha: 0.7)
            self.selectedFee = "high"
            
            if (CGFloat(truncating: NumberFormatter().number(from: ((self.satsFast.text!).replacingOccurrences(of: " sats", with: "").replacingOccurrences(of: ".", with: Locale.current.decimalSeparator!).replacingOccurrences(of: ",", with: Locale.current.decimalSeparator!)))!)) / (CGFloat(truncating: NumberFormatter().number(from: ((self.amountConfirmation.text!).replacingOccurrences(of: ".", with: Locale.current.decimalSeparator!).replacingOccurrences(of: ",", with: Locale.current.decimalSeparator!)))!)*100000000) > 0.1 {
                
                let ac = UIAlertController(title: "High fee rate", message: "The fee you've selected costs more than 10 % of the bitcoin you're sending. Make sure this is as intended.", preferredStyle: .alert)
                ac.addAction(UIAlertAction(title: "Okay", style: .default))
                present(ac, animated: true)
            }
        case "medium":
            self.fastView.backgroundColor = UIColor(white: 1, alpha: 0.7)
            self.mediumView.backgroundColor = UIColor(white: 1, alpha: 1)
            self.slowView.backgroundColor = UIColor(white: 1, alpha: 0.7)
            self.selectedFee = "medium"
            
            if (CGFloat(truncating: NumberFormatter().number(from: ((self.satsMedium.text!).replacingOccurrences(of: " sats", with: "").replacingOccurrences(of: ".", with: Locale.current.decimalSeparator!).replacingOccurrences(of: ",", with: Locale.current.decimalSeparator!)))!)) / (CGFloat(truncating: NumberFormatter().number(from: ((self.amountConfirmation.text!).replacingOccurrences(of: ".", with: Locale.current.decimalSeparator!).replacingOccurrences(of: ",", with: Locale.current.decimalSeparator!)))!)*100000000) > 0.1 {
                
                let ac = UIAlertController(title: "High fee rate", message: "The fee you've selected costs more than 10 % of the bitcoin you're sending. Make sure this is as intended.", preferredStyle: .alert)
                ac.addAction(UIAlertAction(title: "Okay", style: .default))
                present(ac, animated: true)
            }
        case "slow":
            self.fastView.backgroundColor = UIColor(white: 1, alpha: 0.7)
            self.mediumView.backgroundColor = UIColor(white: 1, alpha: 0.7)
            self.slowView.backgroundColor = UIColor(white: 1, alpha: 1)
            self.selectedFee = "low"
            
            if (CGFloat(truncating: NumberFormatter().number(from: ((self.satsSlow.text!).replacingOccurrences(of: " sats", with: "").replacingOccurrences(of: ".", with: Locale.current.decimalSeparator!).replacingOccurrences(of: ",", with: Locale.current.decimalSeparator!)))!)) / (CGFloat(truncating: NumberFormatter().number(from: ((self.amountConfirmation.text!).replacingOccurrences(of: ".", with: Locale.current.decimalSeparator!).replacingOccurrences(of: ",", with: Locale.current.decimalSeparator!)))!)*100000000) > 0.1 {
                
                let ac = UIAlertController(title: "High fee rate", message: "The fee you've selected costs more than 10 % of the bitcoin you're sending. Make sure this is as intended.", preferredStyle: .alert)
                ac.addAction(UIAlertAction(title: "Okay", style: .default))
                present(ac, animated: true)
            }
        default:
            self.fastView.backgroundColor = UIColor(white: 1, alpha: 0.7)
            self.mediumView.backgroundColor = UIColor(white: 1, alpha: 1)
            self.slowView.backgroundColor = UIColor(white: 1, alpha: 0.7)
            self.selectedFee = "medium"
            
            if (CGFloat(truncating: NumberFormatter().number(from: ((self.satsMedium.text!).replacingOccurrences(of: " sats", with: "").replacingOccurrences(of: ".", with: Locale.current.decimalSeparator!).replacingOccurrences(of: ",", with: Locale.current.decimalSeparator!)))!)) / (CGFloat(truncating: NumberFormatter().number(from: ((self.amountConfirmation.text!).replacingOccurrences(of: ".", with: Locale.current.decimalSeparator!).replacingOccurrences(of: ",", with: Locale.current.decimalSeparator!)))!)*100000000) > 0.1 {
                
                let ac = UIAlertController(title: "High fee rate", message: "The fee you've selected costs more than 10 % of the bitcoin you're sending. Make sure this is as intended.", preferredStyle: .alert)
                ac.addAction(UIAlertAction(title: "Okay", style: .default))
                present(ac, animated: true)
            }
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
