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
    @IBOutlet weak var scrollViewBottom: NSLayoutConstraint!
    @IBOutlet weak var contentView: UIView!
    @IBOutlet weak var contentViewHeight: NSLayoutConstraint!
    @IBOutlet weak var centerViewBoth: UIView!
    @IBOutlet weak var contentBackgroundButton: UIButton!
    
    // Main - Switch stack
    @IBOutlet weak var switchStack: UIView!
    @IBOutlet weak var viewRegular: UIView!
    @IBOutlet weak var labelRegular: UILabel!
    @IBOutlet weak var regularButton: UIButton!
    @IBOutlet weak var viewBoth: UIView!
    @IBOutlet weak var labelBoth: UILabel!
    @IBOutlet weak var bothButton: UIButton!
    @IBOutlet weak var viewInstant: UIView!
    @IBOutlet weak var labelInstant: UILabel!
    @IBOutlet weak var iconLightning: UIImageView!
    @IBOutlet weak var instantButton: UIButton!
    @IBOutlet weak var lnurlStack: UIView!
    @IBOutlet weak var lnurlStackWidth: NSLayoutConstraint!
    @IBOutlet weak var viewLnurl: UIView!
    @IBOutlet weak var labelUrl: UILabel!
    @IBOutlet weak var iconLnurl: UIImageView!
    @IBOutlet weak var lnurlButton: UIButton!
    
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
    
    // Main - LNURL view
    @IBOutlet weak var lnurlQRBackground: UIView!
    @IBOutlet weak var lnurlQRCode: UIImageView!
    @IBOutlet weak var lnurlAddressBackground: UIView!
    @IBOutlet weak var lnurlAddressLabel: UILabel!
    @IBOutlet weak var lnurlCopyIcon: UIImageView!
    @IBOutlet weak var lnurlCopyButton: UIButton!
    
    // Amount view
    @IBOutlet weak var amountAndDescriptionStack: UIView!
    @IBOutlet weak var amountAndDescriptionStackHeight: NSLayoutConstraint! // 156 or 0
    @IBOutlet weak var bothAmountLabel: UILabel!
    @IBOutlet weak var bothAmountView: UIView!
    @IBOutlet weak var bothAmountTextField: UITextField!
    @IBOutlet weak var bothAmountButton: UIButton!
    
    // Description view
    @IBOutlet weak var bothDescriptionView: UIView!
    @IBOutlet weak var bothDescriptionTextField: UITextField!
    @IBOutlet weak var bothDescriptionButton: UIButton!
    
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
    @IBOutlet weak var spinnerLabel: UILabel!
    
    // Variables
    var coreVC:CoreViewController?
    var homeVC:HomeViewController?
    var keyboardIsActive = false
    var maximumReceivableLNSats:Int?
    var completedTransaction:Transaction?
    var temporaryInvoiceText = ""
    var temporaryInvoiceAmount = 0
    var temporaryInvoiceNote:String?
    var temporaryIsZeroAmountInvoice = false
    var pendingLightningInvoice = ""
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
        self.lnurlButton.setTitle("", for: .normal)
        self.lnurlCopyButton.setTitle("", for: .normal)
        
        // Corner radii
        self.qrView.layer.cornerRadius = 13
        self.bothQrView.layer.cornerRadius = 13
        self.addressView.layer.cornerRadius = 13
        self.bothAddressView.layer.cornerRadius = 13
        self.refreshView.layer.cornerRadius = 13
        self.bothAmountView.layer.cornerRadius = 13
        self.bothDescriptionView.layer.cornerRadius = 13
        self.createView.layer.cornerRadius = 13
        self.lnConfirmationQRView.layer.cornerRadius = 13
        self.lnConfirmationAddressView.layer.cornerRadius = 13
        self.lnurlQrView.layer.cornerRadius = 13
        self.scannerView.layer.cornerRadius = 13
        self.qrScannerCloseView.layer.cornerRadius = 13
        self.spinnerBox.layer.cornerRadius = 13
        self.viewRegular.layer.cornerRadius = 8
        self.viewBoth.layer.cornerRadius = 8
        self.viewInstant.layer.cornerRadius = 8
        self.viewLnurl.layer.cornerRadius = 8
        self.lnurlQRBackground.layer.cornerRadius = 13
        self.lnurlAddressBackground.layer.cornerRadius = 13
        
        // Text field delegates
        self.bothAmountTextField.delegate = self
        self.bothAmountTextField.addDoneButton(target: self, returnaction: #selector(self.doneButtonTapped))
        self.bothDescriptionTextField.delegate = self
        
        // Receivable sats label
        self.setShadows(forView: self.qrView)
        self.setShadows(forView: self.bothQrView)
        self.setShadows(forView: self.lnConfirmationQRView)
        self.setShadows(forView: self.lnurlQRBackground)
        
        // Create QR code
        self.resetQRs(resetAddress: false)
        
        // Selection view
        self.viewBoth.layer.shadowColor = UIColor.black.cgColor
        self.viewBoth.layer.shadowOffset = CGSize(width: 0, height: 7)
        self.viewBoth.layer.shadowRadius = 10.0
        self.viewBoth.layer.shadowOpacity = 0.1
        self.viewRegular.layer.shadowColor = UIColor.black.cgColor
        self.viewRegular.layer.shadowOffset = CGSize(width: 0, height: 7)
        self.viewRegular.layer.shadowRadius = 10.0
        self.viewInstant.layer.shadowColor = UIColor.black.cgColor
        self.viewInstant.layer.shadowOffset = CGSize(width: 0, height: 7)
        self.viewInstant.layer.shadowRadius = 10.0
        self.viewLnurl.layer.shadowColor = UIColor.black.cgColor
        self.viewLnurl.layer.shadowOffset = CGSize(width: 0, height: 7)
        self.viewLnurl.layer.shadowRadius = 10.0
        
        // Set colors and language.
        self.setWords()
        self.changeColors()
    }
    
    func setShadows(forView:UIView) {
        forView.layer.shadowColor = UIColor.black.cgColor
        forView.layer.shadowOffset = CGSize(width: 0, height: 7)
        forView.layer.shadowRadius = 10.0
        forView.layer.shadowOpacity = 0.1
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
        
        if self.coreVC!.bittrWallet.lightningChannels.count == 0 {
            // User has no Lightning channels. Show Regular QR only.
            
            // Dim labels
            self.labelBoth.alpha = 0.3
            self.labelInstant.alpha = 0.3
            self.iconLightning.alpha = 0.3
            
            // Fix constraints
            self.centerViewRegularTrailing.constant = self.view.bounds.width
            
            self.viewRegular.backgroundColor = Colors.getColor("whiteorblue3")
            self.viewRegular.layer.shadowOpacity = 0.1
            self.viewBoth.backgroundColor = Colors.getColor("white0.7orblue2")
            self.viewBoth.layer.shadowOpacity = 0
        } else if let firstIban = self.coreVC!.bittrWallet.ibanEntities.first, !firstIban.lightningAddressUsername.isEmpty {
            
            // Show LNURL
            self.lnurlStackWidth.constant = self.switchStack.bounds.width * 0.23
            self.view.layoutIfNeeded()
            self.lnurlAddressLabel.text = firstIban.lightningAddressUsername
            self.lnurlQRCode.image = self.generateQRCode(from: firstIban.lightningAddressUsername)
            self.lnurlQRCode.layer.magnificationFilter = .nearest
            self.lnurlStack.alpha = 1
            
        }
    }
    
    override func viewDidAppear(_ animated: Bool) {
        self.checkContentViewHeight()
    }
    
    func checkContentViewHeight() {
        let centerViewHeight = centerViewBoth.bounds.height
        if centerViewBoth.bounds.height + 60 > contentView.bounds.height {
            NSLayoutConstraint.deactivate([self.contentViewHeight])
            self.contentViewHeight = NSLayoutConstraint(item: self.contentView, attribute: .height, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: centerViewHeight + 120)
            NSLayoutConstraint.activate([self.contentViewHeight])
            self.view.layoutIfNeeded()
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        if (captureSession?.isRunning == true) {
            captureSession.stopRunning()
        }
    }
    
    @objc func keyboardWillDisappear() {
        
        self.keyboardIsActive = false
        self.bothAmountButton.alpha = 1
        self.bothDescriptionButton.alpha = 1
        
        self.scrollViewBottom.constant = self.view.safeAreaInsets.bottom
        self.view.layoutIfNeeded()
        self.checkContentViewHeight()
    }
    
    @objc func keyboardWillAppear(_ notification:Notification) {
        
        self.keyboardIsActive = true
        
        if let keyboardSize = (notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue {
            
            // Adjust scroll view bottom to keyboard top.
            let keyboardHeight = keyboardSize.height
            self.scrollViewBottom.constant = -keyboardHeight + self.view.safeAreaInsets.bottom
            self.view.layoutIfNeeded()
            self.checkContentViewHeight()
            
            // Scroll view up to text field.
            var fieldFrame = self.scrollView.convert(self.bothDescriptionTextField.bounds, from: self.bothDescriptionTextField.superview)
            fieldFrame = fieldFrame.insetBy(dx: 0, dy: -25)
            self.scrollView.scrollRectToVisible(fieldFrame, animated: true)
        }
    }
    
    @IBAction func copyAddressTapped(_ sender: UIButton) {
        
        var copyingText = self.addressLabel.text
        if sender.tag == 1 {
            copyingText = self.bothAddressLabel.text
        } else if sender.tag == 2 {
            copyingText = self.lnurlAddressLabel.text
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
        
        if self.coreVC!.bittrWallet.lightningChannels.count == 0, sender.accessibilityIdentifier != "regular" {
            // User doesn't have any Lightning channels.
            self.showAlert(presentingController: self, title: Language.getWord(withID: "instantpayments"), message: Language.getWord(withID: "questionvc13"), buttons: [Language.getWord(withID: "okay")], actions: nil)
            return
        }
        
        // Set shadows
        let shadowOpacities:[[Float]] = [[0.1, 0, 0, 0],[0, 0.1, 0, 0],[0, 0, 0.1, 0],[0, 0, 0, 0.1]]
        self.viewRegular.layer.shadowOpacity = shadowOpacities[sender.tag][0]
        self.viewBoth.layer.shadowOpacity = shadowOpacities[sender.tag][1]
        self.viewInstant.layer.shadowOpacity = shadowOpacities[sender.tag][2]
        self.viewLnurl.layer.shadowOpacity = shadowOpacities[sender.tag][3]
        
        // Colors
        let viewColors:[[UIColor]] = [[Colors.getColor("whiteorblue3"), Colors.getColor("white0.7orblue2"), Colors.getColor("white0.7orblue2"), Colors.getColor("white0.7orblue2")], [Colors.getColor("white0.7orblue2"), Colors.getColor("whiteorblue3"), Colors.getColor("white0.7orblue2"), Colors.getColor("white0.7orblue2")], [Colors.getColor("white0.7orblue2"), Colors.getColor("white0.7orblue2"), Colors.getColor("whiteorblue3"), Colors.getColor("white0.7orblue2")], [Colors.getColor("white0.7orblue2"), Colors.getColor("white0.7orblue2"), Colors.getColor("white0.7orblue2"), Colors.getColor("whiteorblue3")]]
        self.viewRegular.backgroundColor = viewColors[sender.tag][0]
        self.viewBoth.backgroundColor = viewColors[sender.tag][1]
        self.viewInstant.backgroundColor = viewColors[sender.tag][2]
        self.viewLnurl.backgroundColor = viewColors[sender.tag][3]
        
        // Center QR view
        let viewWidths:[CGFloat] = [1, 0, -1, -2]
        let amountStackHeight:[CGFloat] = [156, 156, 156, 0]
        UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseInOut) {
            self.centerViewRegularTrailing.constant = self.view.safeAreaLayoutGuide.layoutFrame.size.width * viewWidths[sender.tag]
            self.amountAndDescriptionStackHeight.constant = amountStackHeight[sender.tag]
            self.amountAndDescriptionStack.alpha = [1, 1, 1, 0][sender.tag]
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
        
        self.coreVC!.launchQuestion(question: Language.getWord(withID: "limitlightning"), answer: Language.getWord(withID: "theresalimit"), type: "lightningreceivable")
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
                    actualTransactionVC.coreVC = self.coreVC
                }
            }
        }
    }
    
}
