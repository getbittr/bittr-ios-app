//
//  ReceiveViewController.swift
//  bittr
//
//  Created by Tom Melters on 05/05/2023.
//

import UIKit
import CoreImage.CIFilterBuiltins
import CodeScanner
import LDKNode
import LDKNodeFFI
import LightningDevKit
import Sentry
import BitcoinDevKit
import AVFoundation

class ReceiveViewController: UIViewController, UITextFieldDelegate, AVCaptureMetadataOutputObjectsDelegate {

    // General
    @IBOutlet weak var downButton: UIButton!
    
    // Main scroll view
    @IBOutlet weak var scrollView: UIScrollView!
    @IBOutlet weak var scrollViewTrailing: NSLayoutConstraint!
    @IBOutlet weak var contentView: UIView!
    @IBOutlet weak var contentViewBottom: NSLayoutConstraint!
    @IBOutlet weak var contentViewHeight: NSLayoutConstraint!
    @IBOutlet weak var centerViewBoth: UIView!
    @IBOutlet weak var centerViewBothCenterY: NSLayoutConstraint!
    @IBOutlet weak var centerViewBottom: NSLayoutConstraint!
    @IBOutlet weak var headerView: UIView!
    @IBOutlet weak var headerLabel: UILabel!
    @IBOutlet weak var contentBackgroundButton: UIButton!
    
    // Main - Switch view
    @IBOutlet weak var switchView: UIView!
    @IBOutlet weak var regularView: UIView!
    @IBOutlet weak var instantView: UIView!
    @IBOutlet weak var regularButton: UIButton!
    @IBOutlet weak var instantButton: UIButton!
    @IBOutlet weak var labelRegular: UILabel!
    @IBOutlet weak var labelInstant: UILabel!
    
    // Main - Regular view
    @IBOutlet weak var centerViewRegular: UIView!
    @IBOutlet weak var centerViewRegularTrailing: NSLayoutConstraint!
    @IBOutlet weak var subtitleRegular: UILabel!
    @IBOutlet weak var qrView: UIView!
    @IBOutlet weak var qrCodeImage: UIImageView!
    @IBOutlet weak var qrCodeLogoView: UIView!
    @IBOutlet weak var qrCodeSpinner: UIActivityIndicatorView!
    @IBOutlet weak var addressView: UIView!
    @IBOutlet weak var addressSpinner: UIActivityIndicatorView!
    @IBOutlet weak var addressLabel: UILabel!
    @IBOutlet weak var addressCopy: UIImageView!
    @IBOutlet weak var copyAddressButton: UIButton!
    @IBOutlet weak var refreshView: UIView!
    @IBOutlet weak var refreshButton: UIButton!
    
    // Main - Instant view
    @IBOutlet weak var centerViewInstant: UIView!
    @IBOutlet weak var subtitleInstant: UILabel!
    @IBOutlet weak var receivableLNLabel: UILabel!
    @IBOutlet weak var receivableButton: UIButton!
    @IBOutlet weak var questionCircle: UIImageView!
    @IBOutlet weak var backgroundButton: UIButton!
    @IBOutlet weak var amountLabel: UILabel!
    @IBOutlet weak var amountView: UIView!
    @IBOutlet weak var amountTextField: UITextField!
    @IBOutlet weak var amountButton: UIButton!
    @IBOutlet weak var descriptionLabel: UILabel!
    @IBOutlet weak var descriptionView: UIView!
    @IBOutlet weak var descriptionTextField: UITextField!
    @IBOutlet weak var descriptionButton: UIButton!
    @IBOutlet weak var createView: UIView!
    @IBOutlet weak var createInvoiceLabel: UILabel!
    @IBOutlet weak var invoiceButton: UIButton!
    @IBOutlet weak var lnurlQrView: UIView!
    @IBOutlet weak var scanQrButton: UIButton!
    
    // QR Scanner
    @IBOutlet weak var qrScannerView: UIView!
    @IBOutlet weak var scannerView: UIView!
    @IBOutlet weak var qrScannerBackgroundButton: UIButton!
    @IBOutlet weak var qrScannerLabel: UILabel!
    @IBOutlet weak var qrScannerCloseView: UIView!
    @IBOutlet weak var qrScannerCloseLabel: UILabel!
    var captureSession: AVCaptureSession!
    var previewLayer: AVCaptureVideoPreviewLayer!
    var scannerWorks = false
    
    // Confirm invoice view
    @IBOutlet weak var lnConfirmationHeaderView: UIView!
    @IBOutlet weak var lnHeaderLabel: UILabel!
    @IBOutlet weak var lnConfirmationLabel: UILabel!
    @IBOutlet weak var lnConfirmationQRView: UIView!
    @IBOutlet weak var lnQRImage: UIImageView!
    @IBOutlet weak var lnQRCodeLogoView: UIView!
    @IBOutlet weak var lnConfirmationAddressView: UIView!
    @IBOutlet weak var lnInvoiceLabel: UILabel!
    @IBOutlet weak var copyInvoiceButton: UIButton!
    @IBOutlet weak var lnConfirmationDoneView: UIView!
    @IBOutlet weak var lnConfirmationDoneButton: UIButton!
    @IBOutlet weak var lnDoneLabel: UILabel!
    
    // Variables
    var keyboardIsActive = false
    var maximumReceivableLNSats:Int?
    var createdInvoice = ""
    
    override func viewDidLoad() {
        super.viewDidLoad()

        // Button titles
        downButton.setTitle("", for: .normal)
        copyAddressButton.setTitle("", for: .normal)
        refreshButton.setTitle("", for: .normal)
        regularButton.setTitle("", for: .normal)
        instantButton.setTitle("", for: .normal)
        amountButton.setTitle("", for: .normal)
        descriptionButton.setTitle("", for: .normal)
        backgroundButton.setTitle("", for: .normal)
        contentBackgroundButton.setTitle("", for: .normal)
        invoiceButton.setTitle("", for: .normal)
        copyInvoiceButton.setTitle("", for: .normal)
        lnConfirmationDoneButton.setTitle("", for: .normal)
        receivableButton.setTitle("", for: .normal)
        scanQrButton.setTitle("", for: .normal)
        qrScannerBackgroundButton.setTitle("", for: .normal)
        
        // Corner radii
        headerView.layer.cornerRadius = 13
        qrView.layer.cornerRadius = 13
        addressView.layer.cornerRadius = 13
        refreshView.layer.cornerRadius = 13
        switchView.layer.cornerRadius = 13
        amountView.layer.cornerRadius = 13
        descriptionView.layer.cornerRadius = 13
        createView.layer.cornerRadius = 13
        lnConfirmationHeaderView.layer.cornerRadius = 13
        lnConfirmationQRView.layer.cornerRadius = 13
        lnConfirmationAddressView.layer.cornerRadius = 13
        lnConfirmationDoneView.layer.cornerRadius = 13
        lnurlQrView.layer.cornerRadius = 13
        scannerView.layer.cornerRadius = 13
        qrScannerCloseView.layer.cornerRadius = 13
        
        // Text field delegates
        amountTextField.delegate = self
        descriptionTextField.delegate = self
        amountTextField.addDoneButton(target: self, returnaction: #selector(self.doneButtonTapped))
        
        // Receivable sats label
        if let actualReceivableLN = maximumReceivableLNSats {
            self.receivableLNLabel.text = "\(Language.getWord(withID: "youcanreceive")) \(actualReceivableLN) satoshis."
        }
        
        // Create QR code
        addressCopy.alpha = 0
        qrCodeImage.alpha = 0
        addressLabel.text = ""
        addressSpinner.startAnimating()
        qrCodeSpinner.startAnimating()
        getNewAddress(resetAddress: false)
        
        // Set colors and language.
        self.setWords()
        self.changeColors()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillDisappear), name: UIResponder.keyboardWillHideNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillAppear), name: UIResponder.keyboardWillShowNotification, object: nil)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        let centerViewHeight = centerViewBoth.bounds.height
        if centerViewBoth.bounds.height + 40 > contentView.bounds.height {
            NSLayoutConstraint.deactivate([self.contentViewHeight])
            self.contentViewHeight = NSLayoutConstraint(item: self.contentView, attribute: .height, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: centerViewHeight + 80)
            NSLayoutConstraint.activate([self.contentViewHeight])
            self.centerViewBothCenterY.constant = 0
            self.view.layoutIfNeeded()
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        if (captureSession?.isRunning == true) {
            captureSession.stopRunning()
        }
    }
    
    @objc func keyboardWillDisappear() {
        
        keyboardIsActive = false
        
        self.descriptionButton.alpha = 1
        self.amountButton.alpha = 1
        
        NSLayoutConstraint.deactivate([contentViewBottom])
        contentViewBottom = NSLayoutConstraint(item: contentView!, attribute: .bottom, relatedBy: .equal, toItem: scrollView, attribute: .bottom, multiplier: 1, constant: 0)
        NSLayoutConstraint.activate([contentViewBottom])
        
        self.view.layoutIfNeeded()
    }
    
    @objc func keyboardWillAppear(_ notification:Notification) {
        
        keyboardIsActive = true
        
        if let keyboardSize = (notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue {
            
            let keyboardHeight = keyboardSize.height
            
            NSLayoutConstraint.deactivate([contentViewBottom])
            contentViewBottom = NSLayoutConstraint(item: contentView!, attribute: .bottom, relatedBy: .equal, toItem: scrollView, attribute: .bottom, multiplier: 1, constant: -keyboardHeight)
            NSLayoutConstraint.activate([contentViewBottom])
            
            self.view.layoutIfNeeded()
        }
    }
    
    @IBAction func copyAddressTapped(_ sender: UIButton) {
        
        UIPasteboard.general.string = self.addressLabel.text
        let alert = UIAlertController(title: Language.getWord(withID: Language.getWord(withID: "copied")), message: self.addressLabel.text, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: Language.getWord(withID: "okay"), style: .cancel, handler: nil))
        self.present(alert, animated: true)
    }
    
    @IBAction func refreshButtonTapped(_ sender: UIButton) {
        
        addressCopy.alpha = 0
        qrCodeImage.alpha = 0
        qrCodeLogoView.alpha = 0
        addressLabel.text = ""
        addressSpinner.startAnimating()
        qrCodeSpinner.startAnimating()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.getNewAddress(resetAddress:true)
        }
    }

    
    func generateQRCode(from string: String) -> UIImage {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        let data = Data(string.utf8)
        filter.setValue(data, forKey: "inputMessage")
        
        if let outputImage = filter.outputImage {
            if let cgimg = context.createCGImage(outputImage, from: outputImage.extent) {
                return UIImage(cgImage: cgimg)
            }
        }
        return UIImage(systemName: "xmark.circle") ?? UIImage()
    }
    
    @IBAction func downButtonTapped(_ sender: UIButton) {
        self.dismiss(animated: true, completion: nil)
    }
    
    @IBAction func switchTapped(_ sender: UIButton) {
        
        //var bottomCenterView:UIView = self.centerViewRegular
        if sender.accessibilityIdentifier == "regular" {
            self.regularView.backgroundColor = UIColor(white: 1, alpha: 1)
            self.instantView.backgroundColor = UIColor(white: 1, alpha: 0.7)
            //bottomCenterView = self.centerViewRegular
        } else {
            self.regularView.backgroundColor = UIColor(white: 1, alpha: 0.7)
            self.instantView.backgroundColor = UIColor(white: 1, alpha: 1)
            //var bottomCenterView = self.centerViewInstant
        }
        
        UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseInOut) {
            
            var viewWidth = self.view.safeAreaLayoutGuide.layoutFrame.size.width
            var centerViewBottomConstant:CGFloat = 100
            if sender.accessibilityIdentifier == "regular" {
                viewWidth = 0
                centerViewBottomConstant = 0
            }
            self.centerViewRegularTrailing.constant = -viewWidth
            self.centerViewBothCenterY.constant = centerViewBottomConstant
            
            self.view.layoutIfNeeded()
        }
    }
    
    @objc func doneButtonTapped() {
        self.amountTextField.resignFirstResponder()
        self.amountButton.alpha = 1
    }
    
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return false
    }
    
    @IBAction func amountButtonTapped(_ sender: UIButton) {
        
        self.amountTextField.becomeFirstResponder()
        self.amountButton.alpha = 0
    }
    
    @IBAction func descriptionButtonTapped(_ sender: UIButton) {
        
        self.descriptionTextField.becomeFirstResponder()
        self.descriptionButton.alpha = 0
    }
    
    @IBAction func backgroundButtonTapped(_ sender: UIButton) {
        self.qrScannerView.alpha = 0
        
        if let actualCaptureSession = captureSession {
            actualCaptureSession.stopRunning()
        }
        
        self.view.endEditing(true)
    }
    
    @IBAction func createInvoiceButtonTapped(_ sender: UIButton) {
        
        if keyboardIsActive == true {
            self.view.endEditing(true)
        } else {
            
            if self.amountTextField.text == nil || self.amountTextField.text?.trimmingCharacters(in: .whitespacesAndNewlines) == "" {
                // Some field was left empty.
            } else {
                let actualAmount = (Int(self.amountTextField.text!) ?? 0) * 1000
                self.receivePayment(amountMsat: UInt64(actualAmount), description: self.descriptionTextField.text ?? "", expirySecs: 3600)
            }
        }
    }
    
    @IBAction func copyInvoiceButtonTapped(_ sender: UIButton) {
        
        if self.createdInvoice != "" {
            UIPasteboard.general.string = self.createdInvoice
            //UIPasteboard.general.string = sender.accessibilityIdentifier
            let alert = UIAlertController(title: Language.getWord(withID: "copied"), message: self.createdInvoice, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: Language.getWord(withID: "okay"), style: .cancel, handler: nil))
            self.present(alert, animated: true)
        }
    }
    
    @IBAction func lnDoneButtonTapped(_ sender: UIButton) {
        
        // Hide confirmation view.
        UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseInOut) {
            NSLayoutConstraint.deactivate([self.scrollViewTrailing])
            self.scrollViewTrailing = NSLayoutConstraint(item: self.scrollView, attribute: .trailing, relatedBy: .equal, toItem: self.view, attribute: .trailing, multiplier: 1, constant: 0)
            NSLayoutConstraint.activate([self.scrollViewTrailing])
            self.view.layoutIfNeeded()
        }
    }
    
    @IBAction func receivableButtonTapped(_ sender: UIButton) {
        
        let notificationDict:[String: Any] = ["question":Language.getWord(withID: "limitlightning"),"answer":Language.getWord(withID: "theresalimit"),"type":"lightningreceivable"]
        NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "question"), object: nil, userInfo: notificationDict) as Notification)
    }
    
    func changeColors() {
        
        self.view.backgroundColor = Colors.getColor(color: "yellowandgrey")
        
        self.subtitleRegular.textColor = Colors.getColor(color: "black")
        self.subtitleInstant.textColor = Colors.getColor(color: "black")
        
        self.amountLabel.textColor = Colors.getColor(color: "black")
        self.descriptionLabel.textColor = Colors.getColor(color: "black")
        self.receivableLNLabel.textColor = Colors.getColor(color: "black")
        self.questionCircle.tintColor = Colors.getColor(color: "black")
        
        self.lnConfirmationLabel.textColor = Colors.getColor(color: "black")
    }
    
    @IBAction func scanQrButtonTapped(_ sender: UIButton) {
        
        self.qrScannerView.alpha = 1
        self.showScannerView()
    }
    
}
