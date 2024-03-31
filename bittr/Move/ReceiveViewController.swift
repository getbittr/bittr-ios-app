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

class ReceiveViewController: UIViewController, UITextFieldDelegate {

    @IBOutlet weak var downButton: UIButton!
    @IBOutlet weak var headerView: UIView!
    @IBOutlet weak var qrView: UIView!
    @IBOutlet weak var addressView: UIView!
    @IBOutlet weak var refreshView: UIView!
    @IBOutlet weak var contentViewBottom: NSLayoutConstraint!
    @IBOutlet weak var contentView: UIView!
    @IBOutlet weak var scrollView: UIScrollView!
    @IBOutlet weak var contentBackgroundButton: UIButton!
    @IBOutlet weak var backgroundButton: UIButton!
    
    @IBOutlet weak var addressLabel: UILabel!
    @IBOutlet weak var addressCopy: UIImageView!
    @IBOutlet weak var addressSpinner: UIActivityIndicatorView!
    @IBOutlet weak var qrcodeSpinner: UIActivityIndicatorView!
    @IBOutlet weak var qrCodeImage: UIImageView!
    @IBOutlet weak var copyAddressButton: UIButton!
    @IBOutlet weak var refreshButton: UIButton!
    let addressViewModel = AddressViewModel()
    
    @IBOutlet weak var switchView: UIView!
    @IBOutlet weak var regularButton: UIButton!
    @IBOutlet weak var instantButton: UIButton!
    @IBOutlet weak var centerViewRegularTrailing: NSLayoutConstraint!
    @IBOutlet weak var regularView: UIView!
    @IBOutlet weak var instantView: UIView!
    
    @IBOutlet weak var amountView: UIView!
    @IBOutlet weak var descriptionView: UIView!
    @IBOutlet weak var createView: UIView!
    @IBOutlet weak var amountTextField: UITextField!
    @IBOutlet weak var amountButton: UIButton!
    @IBOutlet weak var descriptionTextField: UITextField!
    @IBOutlet weak var descriptionButton: UIButton!
    @IBOutlet weak var invoiceButton: UIButton!
    @IBOutlet weak var receivableButton: UIButton!
    
    var keyboardIsActive = false
    var maximumReceivableLNSats:Int?
    @IBOutlet weak var receivableLNLabel: UILabel!
    
    // Lightning invoice confirmation
    @IBOutlet weak var centerViewBottom: NSLayoutConstraint!
    @IBOutlet weak var centerViewRegular: UIView!
    @IBOutlet weak var centerViewInstant: UIView!
    @IBOutlet weak var centerViewBoth: UIView!
    
    @IBOutlet weak var scrollViewTrailing: NSLayoutConstraint!
    @IBOutlet weak var lnConfirmationHeaderView: UIView!
    @IBOutlet weak var lnConfirmationQRView: UIView!
    @IBOutlet weak var lnConfirmationAddressView: UIView!
    @IBOutlet weak var lnInvoiceLabel: UILabel!
    @IBOutlet weak var copyInvoiceButton: UIButton!
    @IBOutlet weak var lnConfirmationDoneButton: UIButton!
    @IBOutlet weak var lnConfirmationDoneView: UIView!
    @IBOutlet weak var lnQRImage: UIImageView!
    var createdInvoice = ""
    
    override func viewDidLoad() {
        super.viewDidLoad()

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
        
        amountTextField.delegate = self
        descriptionTextField.delegate = self
        amountTextField.addDoneButton(target: self, returnaction: #selector(self.doneButtonTapped))
        
        if let actualReceivableLN = maximumReceivableLNSats {
            self.receivableLNLabel.text = "You can receive up to \(actualReceivableLN) satoshis."
        }
        
        NotificationCenter.default.addObserver(self, selector: #selector(setNewAddress), name: NSNotification.Name(rawValue: "setnewaddress"), object: nil)
        
        addressCopy.alpha = 0
        qrCodeImage.alpha = 0
        addressLabel.text = ""
        addressSpinner.startAnimating()
        qrcodeSpinner.startAnimating()
        getNewAddress()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillDisappear), name: UIResponder.keyboardWillHideNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillAppear), name: UIResponder.keyboardWillShowNotification, object: nil)
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
    
    func getNewAddress() {
        Task {
            //await addressViewModel.newFundingAddress()
            do {
                let address = try await LightningNodeService.shared.newFundingAddress()
                DispatchQueue.main.async {
                    self.addressLabel.text = address
                    self.addressCopy.alpha = 1
                    self.qrCodeImage.image = self.generateQRCode(from: "bitcoin:" + address)
                    self.qrCodeImage.layer.magnificationFilter = .nearest
                    self.qrCodeImage.alpha = 1
                    self.addressSpinner.stopAnimating()
                    self.qrcodeSpinner.stopAnimating()
                }
            } catch let error as NodeError {
                let errorString = handleNodeError(error)
                DispatchQueue.main.async {
                    let alert = UIAlertController(title: "Oops!", message: "We couldn't fetch a wallet address. (\(errorString).) Please try again.", preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: "Try again", style: .cancel, handler: {_ in
                        self.getNewAddress()
                    }))
                    alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: {_ in
                        self.addressSpinner.stopAnimating()
                        self.qrcodeSpinner.stopAnimating()
                    }))
                    self.present(alert, animated: true)
                }
            } catch {
                DispatchQueue.main.async {
                    let alert = UIAlertController(title: "Oops!", message: "We couldn't fetch a wallet address. Please try again.", preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: "Try again", style: .cancel, handler: {_ in
                        self.getNewAddress()
                    }))
                    alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: {_ in
                        self.addressSpinner.stopAnimating()
                        self.qrcodeSpinner.stopAnimating()
                    }))
                    self.present(alert, animated: true)
                }
            }
        }
    }
    
    @objc func setNewAddress(notification:NSNotification) {
        
        if let userInfo = notification.userInfo as [AnyHashable:Any]? {
            if let newAddress = userInfo["address"] as? String {
                self.addressLabel.text = newAddress
                self.addressCopy.alpha = 1
                self.qrCodeImage.image = generateQRCode(from: "bitcoin:" + newAddress)
                self.qrCodeImage.layer.magnificationFilter = .nearest
                self.qrCodeImage.alpha = 1
                self.addressSpinner.stopAnimating()
                self.qrcodeSpinner.stopAnimating()
            }
        }
    }
    
    @IBAction func copyAddressTapped(_ sender: UIButton) {
        
        UIPasteboard.general.string = self.addressLabel.text
        let alert = UIAlertController(title: "Copied", message: self.addressLabel.text, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Okay", style: .cancel, handler: nil))
        self.present(alert, animated: true)
    }
    
    @IBAction func refreshButtonTapped(_ sender: UIButton) {
        
        addressCopy.alpha = 0
        qrCodeImage.alpha = 0
        addressLabel.text = ""
        addressSpinner.startAnimating()
        qrcodeSpinner.startAnimating()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.getNewAddress()
        }
        
        //self.receivePayment(amountMsat: 10000000, description: "Hello", expirySecs: 3600)
    }
    
    func getInvoiceHash(invoiceString:String) -> String {
        let result = Bolt11Invoice.fromStr(s: invoiceString)
        //let result = Bolt11Invoice(stringLiteral: invoiceString)
        if result.isOk() {
            if let invoice = result.getValue() {
                print("Invoice parsed successfully: \(invoice)")
                let paymentHash:[UInt8] = invoice.paymentHash()!
                let hexString = paymentHash.map { String(format: "%02x", $0) }.joined()
                return hexString
            } else {
                return "empty"
            }
        } else if let error = result.getError() {
            print("Failed to parse invoice: \(error)")
            return "empty"
        } else {
            return "empty"
        }
    }
    
    func receivePayment(amountMsat: UInt64, description: String, expirySecs: UInt32) {
        Task {
            do {
                let invoice = try await LightningNodeService.shared.receivePayment(
                    amountMsat: amountMsat,
                    description: description,
                    expirySecs: expirySecs
                )
                DispatchQueue.main.async {
                    
                    let invoiceHash = self.getInvoiceHash(invoiceString: invoice)
                    let newTimestamp = Int(Date().timeIntervalSince1970)
                    CacheManager.storeInvoiceTimestamp(hash: invoiceHash, timestamp: newTimestamp)
                    if let actualInvoiceText = self.descriptionTextField.text {
                        CacheManager.storeInvoiceDescription(hash: invoiceHash, desc: actualInvoiceText)
                    }
                    
                    self.lnInvoiceLabel.text = "\(invoice)"
                    self.lnQRImage.image = self.generateQRCode(from: "lightning:" + invoice)
                    self.lnQRImage.layer.magnificationFilter = .nearest
                    self.createdInvoice = invoice
                    
                    // Show confirmation view.
                    UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseInOut) {
                        NSLayoutConstraint.deactivate([self.scrollViewTrailing])
                        self.scrollViewTrailing = NSLayoutConstraint(item: self.scrollView, attribute: .trailing, relatedBy: .equal, toItem: self.view, attribute: .leading, multiplier: 1, constant: 0)
                        NSLayoutConstraint.activate([self.scrollViewTrailing])
                        self.view.layoutIfNeeded()
                    }
                    
                    self.amountTextField.text = nil
                    self.descriptionTextField.text = nil
                }
            } catch let error as NodeError {
                let errorString = handleNodeError(error)
                DispatchQueue.main.async {
                    let alert = UIAlertController(title: "Error", message: errorString.detail, preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: "OK", style: .default))
                    self.present(alert, animated: true)
                }
            } catch {
                DispatchQueue.main.async {
                    let alert = UIAlertController(title: "Unexpected Error", message: error.localizedDescription, preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: "OK", style: .default))
                    self.present(alert, animated: true)
                }
            }
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
            var centerViewBottomConstant:CGFloat = -200
            if sender.accessibilityIdentifier == "regular" {
                viewWidth = 0
                centerViewBottomConstant = 0
            }
            self.centerViewRegularTrailing.constant = -viewWidth
            self.centerViewBottom.constant = centerViewBottomConstant
            
            /*NSLayoutConstraint.deactivate([self.centerViewBottom])
            self.centerViewBottom = NSLayoutConstraint(item: self.centerViewBoth!, attribute: .bottom, relatedBy: .equal, toItem: bottomCenterView, attribute: .bottom, multiplier: 1, constant: 0)
            NSLayoutConstraint.activate([self.centerViewBottom])*/
            
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
        self.view.endEditing(true)
    }
    
    @IBAction func createInvoiceButtonTapped(_ sender: UIButton) {
        
        if keyboardIsActive == true {
            self.view.endEditing(true)
        } else {
            
            if self.amountTextField.text == nil || self.amountTextField.text?.trimmingCharacters(in: .whitespacesAndNewlines) == ""/* || self.descriptionTextField.text == nil || self.descriptionTextField.text?.trimmingCharacters(in: .whitespacesAndNewlines) == ""*/ {
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
            let alert = UIAlertController(title: "Copied", message: self.createdInvoice, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Okay", style: .cancel, handler: nil))
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
        
        let notificationDict:[String: Any] = ["question":"why a limit for instant payments?","answer":"There's a limit to the amount of satoshis you can receive per invoice.\n\nYour bitcoin lightning channel has a size, ten times the amount of your first Bittr purchase. If the size is 10,000 sats and you've already purchased 2,000 sats, you can still receive up to 8,000 sats in total.\n\nPer invoice you can receive up to ten percent of the channel size. If you need more, you can create multiple invoices.\n\nWhen the channel is full, we empty the channel funds into your bitcoin wallet so that you have space again.","type":"lightningreceivable"]
        NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "question"), object: nil, userInfo: notificationDict) as Notification)
    }
    
}
