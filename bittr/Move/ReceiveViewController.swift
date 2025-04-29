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
    @IBOutlet weak var topLabel: UILabel!
    @IBOutlet weak var topIcon: UIImageView!
    
    // Main scroll view
    @IBOutlet weak var scrollView: UIScrollView!
    @IBOutlet weak var scrollViewTrailing: NSLayoutConstraint!
    @IBOutlet weak var contentView: UIView!
    @IBOutlet weak var contentViewBottom: NSLayoutConstraint!
    @IBOutlet weak var contentViewHeight: NSLayoutConstraint!
    @IBOutlet weak var centerViewBoth: UIView!
    @IBOutlet weak var centerViewBothCenterY: NSLayoutConstraint!
    @IBOutlet weak var centerViewBottom: NSLayoutConstraint!
    @IBOutlet weak var contentBackgroundButton: UIButton!
    
    // Main - Switch view
    @IBOutlet weak var switchView: UIView!
    @IBOutlet weak var switchSelectionView: UIView!
    @IBOutlet weak var regularButton: UIButton!
    @IBOutlet weak var bothButton: UIButton!
    @IBOutlet weak var instantButton: UIButton!
    @IBOutlet weak var labelRegular: UILabel!
    @IBOutlet weak var labelBoth: UILabel!
    @IBOutlet weak var labelInstant: UILabel!
    @IBOutlet weak var iconLightning: UIImageView!
    @IBOutlet weak var iconLightningLeading: NSLayoutConstraint!
    @IBOutlet weak var labelRegularLeading: NSLayoutConstraint!
    @IBOutlet weak var labelBothLeading: NSLayoutConstraint!
    @IBOutlet weak var labelInstantTrailing: NSLayoutConstraint!
    @IBOutlet weak var switchSelectionLeading: NSLayoutConstraint!
    @IBOutlet weak var switchSelectionTrailing: NSLayoutConstraint!
    
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
    @IBOutlet weak var createView: UIView!
    @IBOutlet weak var createInvoiceLabel: UILabel!
    @IBOutlet weak var invoiceButton: UIButton!
    @IBOutlet weak var lnurlQrView: UIView!
    @IBOutlet weak var scanQrButton: UIButton!
    @IBOutlet weak var scanQrImage: UIImageView!
    
    // Main - Both view
    @IBOutlet weak var subtitleBoth: UILabel!
    @IBOutlet weak var bothQrView: UIView!
    @IBOutlet weak var bothAddressView: UIView!
    @IBOutlet weak var bothQrCodeImage: UIImageView!
    @IBOutlet weak var bothQrCodeLogoView: UIView!
    @IBOutlet weak var bothQrCodeSpinner: UIActivityIndicatorView!
    @IBOutlet weak var bothAddressLabel: UILabel!
    @IBOutlet weak var bothCopyAddressButton: UIButton!
    @IBOutlet weak var bothAddressCopy: UIImageView!
    
    // Amount view
    @IBOutlet weak var bothAmountLabel: UILabel!
    @IBOutlet weak var bothAmountView: UIView!
    @IBOutlet weak var bothAmountTextField: UITextField!
    @IBOutlet weak var bothAmountButton: UIButton!
    @IBOutlet weak var bothAddView: UIView!
    @IBOutlet weak var bothAddButton: UIButton!
    
    // Description view
    @IBOutlet weak var bothDescriptionView: UIView!
    @IBOutlet weak var bothDescriptionTextField: UITextField!
    @IBOutlet weak var bothDescriptionButton: UIButton!
    @IBOutlet weak var bothDescriptionAddView: UIView!
    @IBOutlet weak var bothDescriptionAddButton: UIButton!
    
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
    @IBOutlet weak var lnConfirmationQRView: UIView!
    @IBOutlet weak var lnQRImage: UIImageView!
    @IBOutlet weak var lnQRCodeLogoView: UIView!
    @IBOutlet weak var lnConfirmationAddressView: UIView!
    @IBOutlet weak var lnInvoiceLabel: UILabel!
    @IBOutlet weak var lnInvoiceCopy: UIImageView!
    @IBOutlet weak var copyInvoiceButton: UIButton!
    
    // LNURL spinner
    @IBOutlet weak var spinnerView: UIView!
    @IBOutlet weak var spinnerBox: UIView!
    @IBOutlet weak var lnurlSpinner: UIActivityIndicatorView!
    
    // Variables
    var keyboardIsActive = false
    var maximumReceivableLNSats:Int?
    var homeVC:HomeViewController?
    var completedTransaction:Transaction?
    var newPaymentHash:PaymentHash?
    var newInvoiceAmount:Int?
    var temporaryInvoiceText = ""
    var temporaryInvoiceAmount = 0
    var didDoublecheckLastUsedAddress = false
    
    override func viewDidLoad() {
        super.viewDidLoad()

        // Button titles
        self.downButton.setTitle("", for: .normal)
        self.copyAddressButton.setTitle("", for: .normal)
        self.bothCopyAddressButton.setTitle("", for: .normal)
        self.refreshButton.setTitle("", for: .normal)
        self.regularButton.setTitle("", for: .normal)
        self.bothButton.setTitle("", for: .normal)
        self.instantButton.setTitle("", for: .normal)
        self.contentBackgroundButton.setTitle("", for: .normal)
        self.invoiceButton.setTitle("", for: .normal)
        self.copyInvoiceButton.setTitle("", for: .normal)
        self.scanQrButton.setTitle("", for: .normal)
        self.qrScannerBackgroundButton.setTitle("", for: .normal)
        self.bothAddButton.setTitle("", for: .normal)
        self.bothDescriptionAddButton.setTitle("", for: .normal)
        
        // Corner radii
        self.qrView.layer.cornerRadius = 13
        self.bothQrView.layer.cornerRadius = 13
        self.addressView.layer.cornerRadius = 13
        self.bothAddressView.layer.cornerRadius = 13
        self.refreshView.layer.cornerRadius = 13
        self.switchView.layer.cornerRadius = 13
        self.bothAmountView.layer.cornerRadius = 13
        self.bothDescriptionView.layer.cornerRadius = 13
        self.bothAddView.layer.cornerRadius = 8
        self.bothDescriptionAddView.layer.cornerRadius = 8
        self.createView.layer.cornerRadius = 13
        self.lnConfirmationQRView.layer.cornerRadius = 13
        self.lnConfirmationAddressView.layer.cornerRadius = 13
        self.lnurlQrView.layer.cornerRadius = 13
        self.scannerView.layer.cornerRadius = 13
        self.qrScannerCloseView.layer.cornerRadius = 13
        self.spinnerBox.layer.cornerRadius = 13
        self.switchSelectionView.layer.cornerRadius = 8
        
        // Text field delegates
        self.bothAmountTextField.delegate = self
        self.bothAmountTextField.addDoneButton(target: self, returnaction: #selector(self.doneButtonTapped))
        self.bothDescriptionTextField.delegate = self
        
        // Receivable sats label
        /*if let actualReceivableLN = maximumReceivableLNSats {
            self.receivableLNLabel.text = "\(Language.getWord(withID: "youcanreceive")) \(actualReceivableLN) satoshis."
        }*/
        
        // Create QR code
        self.resetQRs(resetAddress: false)
        
        // Selection view
        self.switchSelectionView.layer.shadowColor = UIColor.black.cgColor
        self.switchSelectionView.layer.shadowOffset = CGSize(width: 0, height: 7)
        self.switchSelectionView.layer.shadowRadius = 10.0
        self.switchSelectionView.layer.shadowOpacity = 0.1
        
        // Set colors and language.
        self.setWords()
        self.changeColors()
    }
    
    func resetQRs(resetAddress:Bool) {
        
        // QRs
        self.qrCodeImage.alpha = 0
        self.bothQrCodeImage.alpha = 0
        self.lnQRImage.alpha = 0
        self.qrCodeLogoView.alpha = 0
        self.bothQrCodeLogoView.alpha = 0
        self.lnQRCodeLogoView.alpha = 0
        
        // Address labels
        self.addressCopy.alpha = 0
        self.bothAddressCopy.alpha = 0
        self.lnInvoiceCopy.alpha = 0
        self.addressLabel.text = ""
        self.bothAddressLabel.text = ""
        self.lnInvoiceLabel.text = ""
        
        self.addressSpinner.startAnimating()
        self.qrCodeSpinner.startAnimating()
        self.bothQrCodeSpinner.startAnimating()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            self.getNewAddress(resetAddress: resetAddress)
        }
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
        
        self.bothAmountButton.alpha = 1
        self.bothDescriptionButton.alpha = 1
        
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
        
        var copyingText = self.addressLabel.text
        if sender.tag == 1 {
            copyingText = self.bothAddressLabel.text
        }
        UIPasteboard.general.string = copyingText
        self.showAlert(presentingController: self, title: Language.getWord(withID: "copied"), message: copyingText ?? "", buttons: [Language.getWord(withID: "okay")], actions: nil)
    }
    
    @IBAction func refreshButtonTapped(_ sender: UIButton) {
        self.view.endEditing(true)
        self.resetQRs(resetAddress: true)
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
        
        var leadingConstraint = self.labelRegular
        var leadingConstant:CGFloat = -15
        var regularConstraint:CGFloat = 20
        var bothConstraint:CGFloat = 30
        var instantConstraint:CGFloat = 20
        var iconLightningConstraint:CGFloat = 25
        if sender.accessibilityIdentifier == "regular" {
            // Regular
            leadingConstraint = self.labelRegular
            leadingConstant = -15
            bothConstraint = 30
            iconLightningConstraint = 17
        } else if sender.accessibilityIdentifier == "instant" {
            // Instant
            leadingConstraint = self.labelInstant
            leadingConstant = -35
            bothConstraint = 20
            iconLightningConstraint = 30
        } else {
            // Both
            leadingConstraint = self.labelBoth
            leadingConstant = -15
            bothConstraint = 28
            iconLightningConstraint = 28
        }
        
        UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseInOut) {
            
            var viewWidth:CGFloat = 0
            var centerViewBottomConstant:CGFloat = 100
            if sender.accessibilityIdentifier == "regular" {
                viewWidth = self.view.safeAreaLayoutGuide.layoutFrame.size.width
                centerViewBottomConstant = 0
            } else if sender.accessibilityIdentifier == "both" {
                viewWidth = 0
                centerViewBottomConstant = 0
            } else {
                viewWidth = -self.view.safeAreaLayoutGuide.layoutFrame.size.width
                centerViewBottomConstant = 0
            }
            self.centerViewRegularTrailing.constant = viewWidth
            self.centerViewBothCenterY.constant = centerViewBottomConstant
            
            self.labelRegularLeading.constant = regularConstraint
            self.labelInstantTrailing.constant = instantConstraint
            self.labelBothLeading.constant = bothConstraint
            self.iconLightningLeading.constant = iconLightningConstraint
            
            NSLayoutConstraint.deactivate([self.switchSelectionLeading, self.switchSelectionTrailing])
            self.switchSelectionLeading = NSLayoutConstraint(item: self.switchSelectionView, attribute: .leading, relatedBy: .equal, toItem: leadingConstraint, attribute: .leading, multiplier: 1, constant: leadingConstant)
            self.switchSelectionTrailing = NSLayoutConstraint(item: self.switchSelectionView, attribute: .trailing, relatedBy: .equal, toItem: leadingConstraint, attribute: .trailing, multiplier: 1, constant: 15)
            NSLayoutConstraint.activate([self.switchSelectionLeading, self.switchSelectionTrailing])
            
            self.view.layoutIfNeeded()
        }
    }
    
    @objc func doneButtonTapped() {
        self.view.endEditing(true)
        self.bothAmountButton.alpha = 1
        self.bothDescriptionButton.alpha = 1
        self.resetQRs(resetAddress: false)
    }
    
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return false
    }
    
    @IBAction func bothAmountButtonTapped(_ sender: UIButton) {
        
        self.bothAmountTextField.becomeFirstResponder()
        self.bothAmountButton.alpha = 0
    }
    
    @IBAction func bothDescriptionButtonTapped(_ sender: UIButton) {
        self.bothDescriptionTextField.becomeFirstResponder()
        self.bothDescriptionButton.alpha = 0
    }
    
    @IBAction func bothAddButtonTapped(_ sender: UIButton) {
        self.view.endEditing(true)
        self.resetQRs(resetAddress: false)
    }
    
    @IBAction func backgroundButtonTapped(_ sender: UIButton) {
        self.qrScannerView.alpha = 0
        
        if let actualCaptureSession = captureSession {
            actualCaptureSession.stopRunning()
        }
        
        self.view.endEditing(true)
    }
    
    @IBAction func copyInvoiceButtonTapped(_ sender: UIButton) {
        
        UIPasteboard.general.string = self.lnInvoiceLabel.text ?? ""
        self.showAlert(presentingController: self, title: Language.getWord(withID: "copied"), message: self.lnInvoiceLabel.text ?? "", buttons: [Language.getWord(withID: "okay")], actions: nil)
    }
    
    @IBAction func receivableButtonTapped(_ sender: UIButton) {
        
        let notificationDict:[String: Any] = ["question":Language.getWord(withID: "limitlightning"),"answer":Language.getWord(withID: "theresalimit"),"type":"lightningreceivable"]
        NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "question"), object: nil, userInfo: notificationDict) as Notification)
    }
    
    @IBAction func scanQrButtonTapped(_ sender: UIButton) {
        self.qrScannerView.alpha = 1
        self.showScannerView()
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        
        // Show new transaction in TransactionVC.
        if segue.identifier == "ReceiveToTransaction" {
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
    
    @objc func addNewPayment() {
        if self.newPaymentHash != nil, self.newInvoiceAmount != nil {
            self.addNewPaymentToTable(paymentHash: newPaymentHash!, invoiceAmount: self.newInvoiceAmount!, delegate: self)
            self.newInvoiceAmount = nil
            self.newPaymentHash = nil
        }
    }
    
}
