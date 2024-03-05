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
    
    var lightningNodeService:LightningNodeService?
    
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
    
    var feeLow:Float = 0.0
    var feeMedium:Float = 0.0
    var feeHigh:Float = 0.0
    var selectedFee = "medium"
    
    var onchainOrLightning = "onchain"
    var selectedInput = "qr"
    
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
        
        fastView.layer.cornerRadius = 13
        mediumView.layer.cornerRadius = 13
        slowView.layer.cornerRadius = 13
        
        backgroundQR.layer.cornerRadius = 13
        backgroundPaste.layer.cornerRadius = 13
        backgroundKeyboard.layer.cornerRadius = 13
        
        toTextField.delegate = self
        amountTextField.delegate = self
        amountTextField.addDoneButton(target: self, returnaction: #selector(self.doneButtonTapped))
        
        let numberFormatter = NumberFormatter()
        numberFormatter.numberStyle = .decimal
        self.availableAmount.text = "Send all: \(numberFormatter.number(from: "\(self.btcAmount)".replacingOccurrences(of: ".", with: Locale.current.decimalSeparator!).replacingOccurrences(of: ",", with: Locale.current.decimalSeparator!))!.decimalValue as NSNumber)"
        
        /*if let actualPresetAmount = presetAmount {
            
            self.fromLabel.text = "My BTCLN wallet"
            self.toTextField.text = "My BTC wallet"
            self.availableAmount.text = "Send all: \(numberFormatter.number(from: "\(self.btclnAmount)".replacingOccurrences(of: ".", with: Locale.current.decimalSeparator!).replacingOccurrences(of: ",", with: Locale.current.decimalSeparator!))!.decimalValue as NSNumber)"
            self.clipboardWidth.constant = 0
            self.toTextFieldTrailing.constant = 0
            self.amountTextField.text = String(actualPresetAmount)
        }*/
        
        /*let codeScanner = CodeScannerView(codeTypes: [.qr]) { result in
        }*/
        
        fixQrScanner()
        
    }
    
    
    func fixQrScanner() {
        
        captureSession = AVCaptureSession()
        guard let videoCaptureDevice = AVCaptureDevice.default(for: .video) else {
            self.scannerWorks = false
            return
        }
        let videoInput: AVCaptureDeviceInput
        do {
            videoInput = try AVCaptureDeviceInput(device: videoCaptureDevice)
        } catch {
            self.scannerWorks = false
            return
        }
        
        if (captureSession.canAddInput(videoInput)) {
            captureSession.addInput(videoInput)
        } else {
            failed()
            return
        }
        
        let metadataOutput = AVCaptureMetadataOutput()
        
        if (captureSession.canAddOutput(metadataOutput)) {
            captureSession.addOutput(metadataOutput)

            metadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
            metadataOutput.metadataObjectTypes = [.qr]
        } else {
            failed()
            return
        }
        
        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.frame = self.scannerView.layer.bounds
        previewLayer.videoGravity = .resizeAspectFill
        self.scannerView.layer.addSublayer(previewLayer)
        
        //captureSession.startRunning()
        self.scannerWorks = true
    }
    
    func failed() {
        let ac = UIAlertController(title: "Scanning not supported", message: "Your device does not support scanning a code from an item. Please use a device with a camera.", preferredStyle: .alert)
        ac.addAction(UIAlertAction(title: "Okay", style: .default))
        present(ac, animated: true)
        captureSession = nil
        
        self.scannerWorks = false
        
        self.scannerView.alpha = 0
        self.toLabel.alpha = 1
        self.toView.alpha = 1
        self.amountLabel.alpha = 1
        self.amountView.alpha = 1
        self.availableAmount.alpha = 1
        self.availableButton.alpha = 1
        self.nextViewTop.constant = -30
        //self.nextView.alpha = 1
    }
    
    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        
        captureSession.stopRunning()

        if let metadataObject = metadataObjects.first {
            guard let readableObject = metadataObject as? AVMetadataMachineReadableCodeObject else { return }
            guard let stringValue = readableObject.stringValue else { return }
            AudioServicesPlaySystemSound(SystemSoundID(kSystemSoundID_Vibrate))
            found(code: stringValue)
        }
    }
    
    func found(code: String) {
        print("Code: " + code)
        
        if self.onchainOrLightning == "onchain", !code.contains("bitcoin") {
            self.toTextField.text = nil
            self.amountTextField.text = nil
            let ac = UIAlertController(title: "No bitcoin address found.", message: "Please scan a bitcoin address QR code or input the address manually.", preferredStyle: .alert)
            ac.addAction(UIAlertAction(title: "Okay", style: .default))
            present(ac, animated: true)
        } else if self.onchainOrLightning == "lightning", !code.lowercased().contains("ln") {
            self.toTextField.text = nil
            self.amountTextField.text = nil
            let ac = UIAlertController(title: "No lightning address found.", message: "Please scan a lightning address QR code or input the address manually.", preferredStyle: .alert)
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
            
            if self.onchainOrLightning == "onchain" {
                
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
                self.availableAmount.text = "Send all: \(numberFormatter.number(from: "\(self.btcAmount)".replacingOccurrences(of: ".", with: Locale.current.decimalSeparator!).replacingOccurrences(of: ",", with: Locale.current.decimalSeparator!))!.decimalValue as NSNumber)"
                self.availableAmountTop.constant = 10
                self.availableButtonTop.constant = 0
                self.availableAmountCenterX.constant = 0
                self.questionCircle.alpha = 0
            } else {
                
                self.pasteButton.alpha = 1
                self.qrImage.alpha = 1
                self.toTextFieldTrailing.constant = -10
                self.amountView.alpha = 0
                self.amountLabel.alpha = 0
                self.availableAmount.alpha = 1
                self.availableButton.alpha = 1
                self.nextLabel.text = "Pay"
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
            let notificationDict:[String: Any] = ["question":"why a limit for instant payments?","answer":"Your bittr wallet consists of a bitcoin wallet (for regular payments) and a bitcoin lightning channel (for instant payments).\n\nIf you've purchased satoshis into your lightning channel, you can use those to pay lightning invoices.\n\nYou cannot make instant payments that exceed the funds in your lightning channel."]
            NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "question"), object: nil, userInfo: notificationDict) as Notification)
        }
    }
    
    @IBAction func toPasteButtonTapped(_ sender: UIButton) {
        
        captureSession.stopRunning()
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
        
        // Open QR scanner.
        if self.scannerWorks == true {
            
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
        }
    }
    
    @IBAction func keyboardButtonTapped(_ sender: UIButton) {
        
        captureSession.stopRunning()
        
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
        
        if self.nextLabel.text == "Next" {
            
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
                
                self.fromConfirmation.text = self.fromLabel.text
                self.toConfirmation.text = invoiceText
                self.amountConfirmation.text = self.amountTextField.text
                
                if let actualBlockchain = LightningNodeService.shared.getBlockchain(), let actualWallet = LightningNodeService.shared.getWallet() {
                    
                    let actualAddress:String = self.toConfirmation.text!
                    let actualAmount:Int = Int(CGFloat(truncating: NumberFormatter().number(from: ((self.amountConfirmation.text!).replacingOccurrences(of: ".", with: Locale.current.decimalSeparator!).replacingOccurrences(of: ",", with: Locale.current.decimalSeparator!)))!)*100000000)
                    
                    Task {
                        do {
                            let high = try actualBlockchain.estimateFee(target: 1)
                            let medium = try actualBlockchain.estimateFee(target: 3)
                            let low = try actualBlockchain.estimateFee(target: 6)
                            
                            print("High: \(high.asSatPerVb()), Medium: \(medium.asSatPerVb()), Low: \(low.asSatPerVb())")
                            
                            let address = try Address(address: actualAddress)
                            let script = address.scriptPubkey()
                            let txBuilder = TxBuilder().addRecipient(script: script, amount: UInt64(actualAmount))
                            let details = try txBuilder.finish(wallet: actualWallet)
                            let _ = try actualWallet.sign(psbt: details.psbt, signOptions: nil)
                            let tx = details.psbt.extractTx()
                            let size = tx.size()

                            print("Size: \(String(describing: size))")
                            print("High: \(high.asSatPerVb()*Float(size)), Medium: \(medium.asSatPerVb()*Float(size)), Low: \(low.asSatPerVb()*Float(size))")
                            
                            self.satsFast.text = "\(Int(high.asSatPerVb()*Float(size))) sats"
                            self.satsMedium.text = "\(Int(medium.asSatPerVb()*Float(size))) sats"
                            self.satsSlow.text = "\(Int(low.asSatPerVb()*Float(size))) sats"
                            
                            self.feeLow = low.asSatPerVb()
                            self.feeMedium = medium.asSatPerVb()
                            self.feeHigh = high.asSatPerVb()
                            
                            var currencySymbol = "€"
                            var conversionRate:CGFloat = 0
                            var eurAmount = CacheManager.getCachedData(key: "eurvalue") as? CGFloat
                            var chfAmount = CacheManager.getCachedData(key: "chfvalue") as? CGFloat
                            conversionRate = eurAmount ?? 0.0
                            if UserDefaults.standard.value(forKey: "currency") as? String == "CHF" {
                                currencySymbol = "CHF"
                                conversionRate = chfAmount ?? 0.0
                            }
                            
                            var fastText = "\(CGFloat(Int((((CGFloat(high.asSatPerVb()*Float(size)))/100000000)*CGFloat(conversionRate))*100))/100)"
                            if fastText.count == 3 {
                                fastText = fastText + "0"
                            }
                            var mediumText = "\(CGFloat(Int((((CGFloat(medium.asSatPerVb()*Float(size)))/100000000)*CGFloat(conversionRate))*100))/100)"
                            if mediumText.count == 3 {
                                mediumText = mediumText + "0"
                            }
                            var slowText = "\(CGFloat(Int((((CGFloat(medium.asSatPerVb()*Float(size)))/100000000)*CGFloat(conversionRate))*100))/100)"
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
                            }
                        } catch {
                            print("Error: \(error.localizedDescription)")
                            
                            self.nextLabel.alpha = 1
                            self.nextSpinner.stopAnimating()
                            
                            let alert = UIAlertController(title: "Oops!", message: "We couldn't proceed to the next step. Error: \(error.localizedDescription).", preferredStyle: .alert)
                            alert.addAction(UIAlertAction(title: "Okay", style: .default))
                            self.present(alert, animated: true)
                        }
                    }
                }
            }
        } else if self.nextLabel.text == "Pay" {
            
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
                let alert = UIAlertController(title: "Send transaction", message: "Are you sure you want to pay invoice \(invoiceText!)?", preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
                alert.addAction(UIAlertAction(title: "Confirm", style: .default, handler: {_ in
                    
                    self.nextLabel.alpha = 0
                    self.nextSpinner.startAnimating()
                    
                    Task {
                        do {
                            let paymentHash = try await LightningNodeService.shared.sendPayment(invoice: String(invoiceText!.replacingOccurrences(of: " ", with: "")))
                            DispatchQueue.main.async {
                                // Success alert
                                let alert = UIAlertController(title: "Payment successful", message: "Payment hash: \(paymentHash)", preferredStyle: .alert)
                                alert.addAction(UIAlertAction(title: "OK", style: .default))
                                self.present(alert, animated: true)
                                
                                self.nextLabel.alpha = 1
                                self.nextSpinner.stopAnimating()
                                self.toTextField.text = nil
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
                            }
                        } catch {
                            DispatchQueue.main.async {
                                // General error alert
                                
                                self.nextLabel.alpha = 1
                                self.nextSpinner.stopAnimating()
                                
                                let alert = UIAlertController(title: "Unexpected Error", message: error.localizedDescription, preferredStyle: .alert)
                                alert.addAction(UIAlertAction(title: "Okay", style: .default))
                                self.present(alert, animated: true)
                            }
                        }
                    }
                }))
                self.present(alert, animated: true)
            }
        } else if self.nextLabel.text == "Manual input", self.onchainOrLightning == "onchain" {
            
            captureSession.stopRunning()
            
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
                self.availableAmount.text = "Send all: \(numberFormatter.number(from: "\(self.btcAmount)".replacingOccurrences(of: ".", with: Locale.current.decimalSeparator!).replacingOccurrences(of: ",", with: Locale.current.decimalSeparator!))!.decimalValue as NSNumber)"
                self.availableAmountTop.constant = 10
                self.availableButtonTop.constant = 0
                self.availableAmountCenterX.constant = 0
                self.questionCircle.alpha = 0
                
                self.view.layoutIfNeeded()
            }
        } else if self.nextLabel.text == "Manual input", self.onchainOrLightning == "lightning" {
            
            captureSession.stopRunning()
            
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
                self.nextLabel.text = "Pay"
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
        
        let alert = UIAlertController(title: "Send transaction", message: "Are you sure you want to send \(self.amountConfirmation.text ?? "these") btc to \(self.toConfirmation.text ?? "this address")?", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        alert.addAction(UIAlertAction(title: "Confirm", style: .default, handler: {_ in 
            
            self.sendLabel.alpha = 0
            self.sendSpinner.startAnimating()
            
            if let actualWallet = LightningNodeService.shared.getWallet(), let actualBlockchain = LightningNodeService.shared.getBlockchain() {
                
                let actualAmount:Int = Int(CGFloat(truncating: NumberFormatter().number(from: ((self.amountConfirmation.text!).replacingOccurrences(of: ".", with: Locale.current.decimalSeparator!).replacingOccurrences(of: ",", with: Locale.current.decimalSeparator!)))!)*100000000)
                
                // tb1qw2c3lxufxqe2x9s4rdzh65tpf4d7fssjgh8nv6
                let actualAddress:String = self.toConfirmation.text!
                
                Task {
                    do {
                        let address = try Address(address: actualAddress)
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
                            /*NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "resetwallet"), object: nil, userInfo: nil) as Notification)*/
                            self.sendLabel.alpha = 1
                            self.sendSpinner.stopAnimating()
                            
                            let successAlert = UIAlertController(title: "Success", message: "Your transaction has been sent and will show up in your wallet shortly.", preferredStyle: .alert)
                            successAlert.addAction(UIAlertAction(title: "Okay", style: .default, handler: {_ in
                                self.dismiss(animated: true)
                            }))
                            self.present(successAlert, animated: true)
                        }
                    } catch {
                        print("Transaction error: \(error.localizedDescription)")
                    }
                }
            } else {
                print("Wallet or Blockchain instance not available.")
            }
        }))
        self.present(alert, animated: true)
    }
    
    
    @IBAction func switchTapped(_ sender: UIButton) {
        
        self.invoiceLabel.text = nil
        self.toTextFieldHeight.constant = 0
        self.toTextField.text = nil
        self.amountTextField.text = nil
        self.toTextFieldTop.constant = 5
        self.invoiceLabelTop.constant = 10
        captureSession.stopRunning()
        
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
                self.availableAmount.text = "Send all: \(numberFormatter.number(from: "\(self.btcAmount)".replacingOccurrences(of: ".", with: Locale.current.decimalSeparator!).replacingOccurrences(of: ",", with: Locale.current.decimalSeparator!))!.decimalValue as NSNumber)"
                self.availableAmountTop.constant = 10
                self.availableButtonTop.constant = 0
                self.availableAmountCenterX.constant = 0
                self.questionCircle.alpha = 0
                
                self.view.layoutIfNeeded()
            }
            
            /*UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseInOut) {
                
                if self.scannerWorks == true {
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
                    
                    if (self.captureSession?.isRunning == false) {
                        self.captureSession.startRunning()
                    }
                } else {
                    self.toLabel.alpha = 1
                    self.toView.alpha = 1
                    self.pasteButton.alpha = 0
                    self.qrImage.alpha = 0
                    self.toTextFieldTrailing.constant = 20
                    self.amountView.alpha = 1
                    self.amountLabel.alpha = 1
                    self.availableAmount.alpha = 1
                    self.availableButton.alpha = 1
                    //self.nextView.alpha = 1
                    self.scannerView.alpha = 0
                    self.nextLabel.text = "Next"
                    self.nextViewTop.constant = -30
                    
                    let numberFormatter = NumberFormatter()
                    numberFormatter.numberStyle = .decimal
                    self.availableAmount.text = "Send all: \(numberFormatter.number(from: "\(self.btcAmount)".replacingOccurrences(of: ".", with: Locale.current.decimalSeparator!).replacingOccurrences(of: ",", with: Locale.current.decimalSeparator!))!.decimalValue as NSNumber)"
                    self.availableAmountTop.constant = 10
                    self.availableButtonTop.constant = 0
                    self.availableAmountCenterX.constant = 0
                    self.questionCircle.alpha = 0
                }
                
                self.view.layoutIfNeeded()
            }*/
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
                self.nextLabel.text = "Pay"
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
            
            /*UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseInOut) {
                
                // TODO:
                
                if self.scannerWorks == true {
                    self.toLabel.alpha = 0
                    self.toView.alpha = 0
                    self.pasteButton.alpha = 0
                    self.qrImage.alpha = 0
                    self.toTextFieldTrailing.constant = -10
                    self.amountView.alpha = 0
                    self.amountLabel.alpha = 0
                    self.availableAmount.alpha = 0
                    self.availableButton.alpha = 0
                    self.scannerView.alpha = 1
                    self.nextLabel.text = "Manual input"
                    
                    NSLayoutConstraint.deactivate([self.nextViewTop])
                    self.nextViewTop = NSLayoutConstraint(item: self.nextView, attribute: .top, relatedBy: .equal, toItem: self.scannerView, attribute: .bottom, multiplier: 1, constant: 30)
                    NSLayoutConstraint.activate([self.nextViewTop])
                    
                    if (self.captureSession?.isRunning == false) {
                        self.captureSession.startRunning()
                    }
                } else {
                    self.pasteButton.alpha = 0
                    self.qrImage.alpha = 0
                    self.toTextFieldTrailing.constant = 20
                    self.amountView.alpha = 0
                    self.amountLabel.alpha = 0
                    //self.availableAmount.alpha = 0
                    self.availableButton.alpha = 1
                    self.nextLabel.text = "Pay"
                    self.nextViewTop.constant = -120
                    self.scannerView.alpha = 0
                    self.toLabel.alpha = 1
                    self.toView.alpha = 1
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
                }
                
                self.view.layoutIfNeeded()
            }*/
        }
    }
    
    @IBAction func feeButtonTapped(_ sender: UIButton) {
        
        switch sender.accessibilityIdentifier! {
        case "fast":
            self.fastView.backgroundColor = UIColor(white: 1, alpha: 1)
            self.mediumView.backgroundColor = UIColor(white: 1, alpha: 0.7)
            self.slowView.backgroundColor = UIColor(white: 1, alpha: 0.7)
            self.selectedFee = "high"
        case "medium":
            self.fastView.backgroundColor = UIColor(white: 1, alpha: 0.7)
            self.mediumView.backgroundColor = UIColor(white: 1, alpha: 1)
            self.slowView.backgroundColor = UIColor(white: 1, alpha: 0.7)
            self.selectedFee = "medium"
        case "slow":
            self.fastView.backgroundColor = UIColor(white: 1, alpha: 0.7)
            self.mediumView.backgroundColor = UIColor(white: 1, alpha: 0.7)
            self.slowView.backgroundColor = UIColor(white: 1, alpha: 1)
            self.selectedFee = "low"
        default:
            self.fastView.backgroundColor = UIColor(white: 1, alpha: 0.7)
            self.mediumView.backgroundColor = UIColor(white: 1, alpha: 1)
            self.slowView.backgroundColor = UIColor(white: 1, alpha: 0.7)
            self.selectedFee = "medium"
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
