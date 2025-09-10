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

    // General
    @IBOutlet weak var downButton: UIButton!
    @IBOutlet weak var topIcon: UIImageView!
    @IBOutlet weak var sendBitcoinLabel: UILabel!
    
    // Main scroll view
    @IBOutlet weak var scrollView: UIScrollView!
    @IBOutlet weak var scrollViewTrailing: NSLayoutConstraint!
    @IBOutlet weak var contentView: UIView!
    @IBOutlet weak var contentViewBottom: NSLayoutConstraint!
    @IBOutlet weak var backgroundButton: UIButton!
    @IBOutlet weak var centerView: UIView!
    @IBOutlet weak var centerBackgroundButton: UIButton!
    
    // Main scroll - Switch view
    @IBOutlet weak var switchView: UIView!
    @IBOutlet weak var switchSelectionView: UIView!
    @IBOutlet weak var regularButton: UIButton!
    @IBOutlet weak var instantButton: UIButton!
    @IBOutlet weak var labelRegular: UILabel!
    @IBOutlet weak var labelInstant: UILabel!
    @IBOutlet weak var iconLightning: UIImageView!
    @IBOutlet weak var labelRegularLeading: NSLayoutConstraint!
    @IBOutlet weak var labelInstantTrailing: NSLayoutConstraint!
    @IBOutlet weak var selectionLeading: NSLayoutConstraint!
    @IBOutlet weak var selectionTrailing: NSLayoutConstraint!
    
    // Main scroll - Items
    @IBOutlet weak var toLabel: UILabel! // Address or Invoice
    
    // Main scroll - To view
    @IBOutlet weak var addressStack: UIView!
    @IBOutlet weak var toView: UIView! // Background
    @IBOutlet weak var toTextField: UITextField! // Text field
    @IBOutlet weak var toButton: UIButton!
    @IBOutlet weak var backgroundQR: UIView!
    @IBOutlet weak var backgroundPaste: UIView!
    @IBOutlet weak var qrButton: UIButton!
    @IBOutlet weak var pasteButton: UIButton!
    @IBOutlet weak var stackLabelQR: UILabel!
    @IBOutlet weak var stackLabelPaste: UILabel!
    @IBOutlet weak var stackImageQR: UIImageView!
    @IBOutlet weak var stackImagePaste: UIImageView!
    
    // Main scroll - Amount view
    @IBOutlet weak var amountStack: UIView!
    @IBOutlet weak var btcView: UIView!
    @IBOutlet weak var btcLabel: UILabel!
    @IBOutlet weak var btcButton: UIButton!
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
    @IBOutlet weak var timeFast: UILabel!
    @IBOutlet weak var timeMedium: UILabel!
    @IBOutlet weak var timeSlow: UILabel!
    @IBOutlet weak var fastButton: UIButton!
    @IBOutlet weak var mediumButton: UIButton!
    @IBOutlet weak var slowButton: UIButton!
    @IBOutlet weak var slowTimeLabel: UILabel!
    
    // Spinner view
    @IBOutlet weak var spinnerView: UIView!
    @IBOutlet weak var spinnerBox: UIView!
    @IBOutlet weak var lnurlSpinner: UIActivityIndicatorView!
    
    // Variables
    var coreVC:CoreViewController?
    var maximumSendableOnchainBtc:Double?
    var completedTransaction:Transaction?
    var onchainAmountInSatoshis:Int = 0
    var newTxId = ""
    var bitcoinQR = ""
    var pendingLightningInvoice = ""
    var pendingOnchainAddress = ""
    
    // User selected variables
    var selectedCurrency:SelectedCurrency = .bitcoin
    var onchainOrLightning:OnchainOrLightning = .onchain
    
    // Temporary invoice variables
    var temporaryInvoiceText = ""
    var temporaryInvoiceAmount = 0
    var temporaryInvoiceNote:String?
    var temporaryIsZeroAmountInvoice = false
    
    // Fees
    var feeLow:Float = 0.0
    var feeMedium:Float = 0.0
    var feeHigh:Float = 0.0
    var selectedFee:SelectedFee = .medium
    var selectedFeeInSats = 0
    
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
        toButton.setTitle("", for: .normal)
        btcButton.setTitle("", for: .normal)
        
        // Corner radii
        toView.layer.cornerRadius = 8
        amountView.layer.cornerRadius = 8
        nextView.layer.cornerRadius = 13
        confirmHeaderView.layer.cornerRadius = 13
        editView.layer.cornerRadius = 13
        sendView.layer.cornerRadius = 13
        switchView.layer.cornerRadius = 13
        switchSelectionView.layer.cornerRadius = 8
        scannerView.layer.cornerRadius = 13
        yellowCard.layer.cornerRadius = 20
        confirmToCard.layer.cornerRadius = 8
        confirmAmountCard.layer.cornerRadius = 8
        fastView.layer.cornerRadius = 8
        mediumView.layer.cornerRadius = 8
        slowView.layer.cornerRadius = 8
        backgroundQR.layer.cornerRadius = 8
        backgroundPaste.layer.cornerRadius = 8
        spinnerBox.layer.cornerRadius = 13
        btcView.layer.cornerRadius = 8
        
        // Shadows
        setShadows(forView: yellowCard)
        setShadows(forView: fastView)
        setShadows(forView: mediumView)
        setShadows(forView: slowView)
        setShadows(forView: backgroundQR)
        setShadows(forView: backgroundPaste)
        setShadows(forView: btcView)
        setShadows(forView: switchSelectionView)
        
        // Text fields
        toTextField.delegate = self
        amountTextField.delegate = self
        toTextField.autocorrectionType = .no
        toTextField.autocapitalizationType = .none
        toTextField.smartQuotesType = .no
        toTextField.smartDashesType = .no
        amountTextField.inputAccessoryView = createAmountInputAccessoryView()
        
        // Set colors and language
        self.changeColors()
        self.setWords()
        self.setSendAllLabel(forView: .onchain)
    }
    
    func setShadows(forView:UIView) {
        forView.layer.shadowColor = UIColor.black.cgColor
        forView.layer.shadowOffset = CGSize(width: 0, height: 7)
        forView.layer.shadowRadius = 10.0
        forView.layer.shadowOpacity = 0.1
    }
    
    func setSendAllLabel(forView:OnchainOrLightning) {
        
        if forView == .onchain {
            // Set "Send all" for onchain transactions.
            if self.maximumSendableOnchainBtc == nil {
                self.maximumSendableOnchainBtc = self.getMaximumSendableSats(coreVC:self.coreVC!) ?? 0
            }
            let formattedAmount = formatBitcoinAmount(self.maximumSendableOnchainBtc ?? self.coreVC!.bittrWallet.satoshisOnchain.inBTC())
            self.availableAmount.text = Language.getWord(withID:"sendall").replacingOccurrences(of: "<amount>", with: formattedAmount)
        } else {
            // Set "Send all" for lightning payments.
            self.availableAmount.text = Language.getWord(withID:"youcansend").replacingOccurrences(of: "<amount>", with: String((self.coreVC?.bittrWallet.lightningChannels.first?.outboundCapacityMsat ?? 0)/1000).addSpaces())
        }
    }
    
    func formatBitcoinAmount(_ btcValue: Double) -> String {
        // Debug: print the values to see what's happening
        print("Debug - btcValue: \(btcValue)")
        
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 8
        formatter.maximumFractionDigits = 8
        
        // Handle very small amounts (less than 1 satoshi)
        if btcValue < 0.00000001 {
            return "0.00000000"
        }
        
        let result = formatter.string(from: NSNumber(value: btcValue)) ?? "0.00000000"
        print("Debug - formatted result: \(result)")
        return result
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
        self.toButton.alpha = 1
        
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
    
    @IBAction func amountButtonTapped(_ sender: UIButton) {
        self.amountTextField.becomeFirstResponder()
        self.amountButton.alpha = 0
    }
    
    @IBAction func toButtonTapped(_ sender: UIButton) {
        self.toTextField.becomeFirstResponder()
        self.toButton.alpha = 0
    }
    
    @objc func doneButtonTapped() {
        // Only handle amount field since address field doesn't have a Done button
        if amountTextField.isFirstResponder {
            // Move to next step
            amountTextField.resignFirstResponder()
            self.nextButtonTapped(nextButton)
        }
    }
    
    // MARK: - UITextFieldDelegate
    
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        // Same logic as doneButtonTapped for return key
        if textField == toTextField {
            // If it's a lightning invoice with amount, go straight to confirmation
            if (textField.text ?? "").prefix(2) == "ln" {
                if let parsedInvoice = Bindings.Bolt11Invoice.fromStr(s: textField.text!).getValue() {
                    if let invoiceAmountMilli = parsedInvoice.amountMilliSatoshis() {
                        // Invoice has amount, go straight to confirmation
                        let invoiceAmount = Int(invoiceAmountMilli)/1000
                        self.amountTextField.text = "\(invoiceAmount)"
                        self.btcLabel.text = "Sats"
                        self.selectedCurrency = .satoshis
                        self.confirmLightningTransaction(lnurlinvoice: nil, sendVC: self, receiveVC: nil, lnurlNote: nil)
                        return true
                    }
                }
            }
            
            // Otherwise, move to amount field
            amountTextField.becomeFirstResponder()
            return true
        } else if textField == amountTextField {
            // Move to next step
            self.nextButtonTapped(nextButton)
            return true
        }
        
        return false
    }
    

    
    // MARK: - UITextFieldDelegate
    

    
    func createAmountInputAccessoryView() -> UIView {
        let containerView = UIView(frame: CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: 44))
        containerView.backgroundColor = Colors.getColor("whiteorblue3")
        
        let toolbar = UIToolbar(frame: containerView.bounds)
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        toolbar.backgroundColor = .clear
        
        // Currency selection buttons
        let btcButton = UIBarButtonItem(title: "BTC", style: .plain, target: self, action: #selector(selectBTCCurrency))
        let satsButton = UIBarButtonItem(title: "Sats", style: .plain, target: self, action: #selector(selectSatsCurrency))
        let currencyButton = UIBarButtonItem(title: UserDefaults.standard.value(forKey: "currency") as? String ?? "EUR", style: .plain, target: self, action: #selector(selectFiatCurrency))
        
        // Style the buttons with better contrast for dark mode
        // Force black color for better visibility in dark mode
        let buttonColor = UIColor.black
        btcButton.tintColor = buttonColor
        satsButton.tintColor = buttonColor
        currencyButton.tintColor = buttonColor
        
        let flexSpace = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        let doneButton = UIBarButtonItem(title: Language.getWord(withID: "done"), style: .done, target: self, action: #selector(doneButtonTapped))
        doneButton.tintColor = buttonColor
        
        toolbar.items = [btcButton, satsButton, currencyButton, flexSpace, doneButton]
        
        containerView.addSubview(toolbar)
        
        NSLayoutConstraint.activate([
            toolbar.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            toolbar.topAnchor.constraint(equalTo: containerView.topAnchor),
            toolbar.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])
        
        return containerView
    }
    
    @objc func selectBTCCurrency() {
        self.btcLabel.text = "BTC"
        self.selectedCurrency = .bitcoin
    }
    
    @objc func selectSatsCurrency() {
        self.btcLabel.text = "Sats"
        self.selectedCurrency = .satoshis
    }
    
    @objc func selectFiatCurrency() {
        let currency = UserDefaults.standard.value(forKey: "currency") as? String ?? "EUR"
        self.btcLabel.text = currency
        self.selectedCurrency = .currency
    }
    
    @IBAction func availableButtonTapped(_ sender: UIButton) {
        
        if self.onchainOrLightning == .onchain {
            // Regular
            let formattedAmount = formatBitcoinAmount(self.maximumSendableOnchainBtc ?? self.coreVC!.bittrWallet.satoshisOnchain.inBTC())
            self.amountTextField.text = formattedAmount
            self.btcLabel.text = "BTC"
            self.selectedCurrency = .bitcoin
        } else {
            // Instant
            self.coreVC!.launchQuestion(question: Language.getWord(withID: "limitlightning"), answer: Language.getWord(withID: "limitlightninganswer"), type: "lightningsendable")
        }
    }
    
    @IBAction func toPasteButtonTapped(_ sender: UIButton) {
        
        if let actualCaptureSession = captureSession {
            actualCaptureSession.stopRunning()
        }
        self.view.endEditing(true)
        if let actualString = UIPasteboard.general.string {
            if !actualString.contains("bitcoin"), !actualString.lowercased().contains("ln") {
                self.toTextField.text = actualString
            } else {
                self.handleScannedOrPastedString(actualString, scanned: false)
            }
        }
    }
    
    @IBAction func qrButtonTapped(_ sender: UIButton) {
        self.view.endEditing(true)
        self.showScannerView()
    }
    
    @IBAction func keyboardButtonTapped(_ sender: UIButton) {
        
        if let actualCaptureSession = captureSession {
            actualCaptureSession.stopRunning()
        }
        self.toTextField.becomeFirstResponder()
    }
    
    @IBAction func backgroundButtonTapped(_ sender: UIButton) {
        self.view.endEditing(true)
    }
    
    @IBAction func nextButtonTapped(_ sender: UIButton) {
        self.view.endEditing(true)
        
        if self.nextLabel.text == Language.getWord(withID: "next") && self.onchainOrLightning == .onchain {
            // Check onchain transaction.
            self.checkSendOnchain()
        } else if self.nextLabel.text == Language.getWord(withID: "next") && self.onchainOrLightning == .lightning {
            // Confirm lightning payment.
            
            // Check if address/invoice field is empty
            if (self.toTextField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines) == "" {
                self.showAlert(presentingController: self, title: Language.getWord(withID: "oops"), message: Language.getWord(withID: "enteraddress"), buttons: [Language.getWord(withID: "okay")], actions: nil)
                return
            }
            
            if (self.amountTextField.text ?? "") == "" {
                if (self.toTextField.text ?? "").prefix(2) == "ln" {
                    if let parsedInvoice = Bindings.Bolt11Invoice.fromStr(s: self.toTextField.text!).getValue() {
                        if let invoiceAmountMilli = parsedInvoice.amountMilliSatoshis() {
                            let invoiceAmount = Int(invoiceAmountMilli)/1000
                            self.amountTextField.text = "\(invoiceAmount)"
                            self.btcLabel.text = "Sats"
                            self.selectedCurrency = .satoshis
                            self.confirmLightningTransaction(lnurlinvoice: nil, sendVC: self, receiveVC: nil, lnurlNote: nil)
                        } else {
                            // Zero invoice.
                            self.showAlert(presentingController: self, title: Language.getWord(withID: "invoice"), message: Language.getWord(withID: "amountmissing"), buttons: [Language.getWord(withID: "okay")], actions: nil)
                        }
                    } else {
                        // Invalid lightning invoice
                        self.showAlert(presentingController: self, title: Language.getWord(withID: "oops"), message: Language.getWord(withID: "enteramount"), buttons: [Language.getWord(withID: "okay")], actions: nil)
                    }
                } else {
                    // Not a lightning invoice, amount is required
                    self.showAlert(presentingController: self, title: Language.getWord(withID: "oops"), message: Language.getWord(withID: "enteramount"), buttons: [Language.getWord(withID: "okay")], actions: nil)
                }
            } else {
                // Transfer to satoshis.
                var satoshisValue = Int(self.stringToNumber(self.amountTextField.text))
                if self.selectedCurrency == .bitcoin {
                    satoshisValue = self.stringToNumber(self.amountTextField.text).inSatoshis()
                } else if self.selectedCurrency == .currency {
                    let bitcoinValue = self.getCorrectBitcoinValue(coreVC: self.coreVC!)
                    satoshisValue = (self.stringToNumber(self.amountTextField.text)/bitcoinValue.currentValue).inSatoshis()
                }
                self.amountTextField.text = "\(satoshisValue)"
                self.btcLabel.text = "Sats"
                self.selectedCurrency = .satoshis
                self.confirmLightningTransaction(lnurlinvoice: nil, sendVC: self, receiveVC: nil, lnurlNote: nil)
            }
        } else if self.nextLabel.text == Language.getWord(withID: "manualinput"), self.onchainOrLightning == .onchain {
            // Hide QR scanner, show onchain.
            self.hideScannerView(forView: .onchain)
        } else if self.nextLabel.text == Language.getWord(withID: "manualinput"), self.onchainOrLightning == .lightning {
            // Hide QR scanner, show lightning.
            self.hideScannerView(forView: .lightning)
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
                    actualTransactionVC.coreVC = self.coreVC
                }
            }
        }
    }
    
    
    @IBAction func switchTapped(_ sender: UIButton) {
        
        if (sender.accessibilityIdentifier ?? "") == "onchain", self.bitcoinQR != "" {
            self.toTextField.text = self.bitcoinQR
        } else {
            // Reset fields.
            self.resetFields()
        }
        
        // Switch view.
        if sender.accessibilityIdentifier != nil {
            if sender.accessibilityIdentifier! == "onchain" {
                self.onchainOrLightning = .onchain
            } else {
                self.onchainOrLightning = .lightning
            }
        }
        self.hideScannerView(forView: self.onchainOrLightning)
    }
    
    @IBAction func feeButtonTapped(_ sender: UIButton) {
        if sender.accessibilityIdentifier! == "high" {
            self.switchFeeSelection(tappedFee: .high)
        } else if sender.accessibilityIdentifier! == "medium" {
            self.switchFeeSelection(tappedFee: .medium)
        } else {
            self.switchFeeSelection(tappedFee: .low)
        }
    }
    
    @IBAction func btcButtonTapped(_ sender: UIButton) {
        
        let actionSheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        let btcOption = UIAlertAction(title: "Bitcoin", style: .default) { (action) in
            self.btcLabel.text = "BTC"
            self.selectedCurrency = .bitcoin
        }
        let satsOption = UIAlertAction(title: "Satoshis", style: .default) { (action) in
            self.btcLabel.text = "Sats"
            self.selectedCurrency = .satoshis
        }
        let bitcoinValue = self.getCorrectBitcoinValue(coreVC: self.coreVC!)
        let currencyOption = UIAlertAction(title: bitcoinValue.chosenCurrency, style: .default) { (action) in
            self.btcLabel.text = bitcoinValue.chosenCurrency
            self.selectedCurrency = .currency
        }
        let cancelAction = UIAlertAction(title: Language.getWord(withID: "cancel"), style: .cancel, handler: nil)
        actionSheet.addAction(btcOption)
        actionSheet.addAction(satsOption)
        actionSheet.addAction(currencyOption)
        actionSheet.addAction(cancelAction)
        present(actionSheet, animated: true, completion: nil)
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

extension UIViewController {
    
    func checkInternetConnection() -> Bool {
        // Check internet connection.
        if !Reachability.isConnectedToNetwork() {
            // User not connected to internet.
            self.showAlert(presentingController: self, title: Language.getWord(withID: "checkyourconnection"), message: Language.getWord(withID: "trytoconnect"), buttons: [Language.getWord(withID: "okay")], actions: nil)
            return false
        } else {
            return true
        }
    }
}

extension String {
    
    func fixDecimals() -> String {
        return self.replacingOccurrences(of: ".", with: Locale.current.decimalSeparator!).replacingOccurrences(of: ",", with: Locale.current.decimalSeparator!)
    }
}

enum OnchainOrLightning {
    case onchain
    case lightning
}

enum SelectedCurrency {
    case bitcoin
    case satoshis
    case currency
}

enum SelectedFee {
    case low
    case medium
    case high
}
