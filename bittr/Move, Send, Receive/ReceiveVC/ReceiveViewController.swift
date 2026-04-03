//
//  ReceiveViewController.swift
//  bittr
//
//  Created by Tom Melters on 05/05/2023.
//

import UIKit
import CoreImage.CIFilterBuiltins
import LDKNode
import Sentry

class ReceiveViewController: UIViewController, UITextFieldDelegate {
    
    // Generic
    @IBOutlet weak var yellowCard: UIView!
    @IBOutlet weak var qrWhiteView: UIView!
    @IBOutlet weak var qrImageView: UIImageView!
    @IBOutlet weak var addressView: UIView!
    @IBOutlet weak var boltStack: UIView!
    @IBOutlet weak var boltStackWidth: NSLayoutConstraint! // 0 or 19
    @IBOutlet weak var addressTitle: UILabel!
    @IBOutlet weak var addressLabel: UILabel!
    
    // Main scroll view
    @IBOutlet weak var scrollView: UIScrollView!
    @IBOutlet weak var scrollViewTrailing: NSLayoutConstraint!
    @IBOutlet weak var scrollViewBottom: NSLayoutConstraint!
    @IBOutlet weak var contentView: UIView!
    @IBOutlet weak var contentViewHeight: NSLayoutConstraint!
    @IBOutlet weak var centerView: UIView!
    @IBOutlet weak var contentBackgroundButton: UIButton!
    
    // Amount view
    @IBOutlet weak var amountAndDescriptionStack: UIView!
    @IBOutlet weak var amountAndDescriptionStackHeight: NSLayoutConstraint! // 156 or 0
    @IBOutlet weak var bothAmountLabel: UILabel!
    @IBOutlet weak var bothAmountView: UIView!
    @IBOutlet weak var bothAmountTextField: UITextField!
    @IBOutlet weak var bothAmountButton: UIButton!
    
    // Currency selection
    @IBOutlet weak var btcView: UIView!
    @IBOutlet weak var btcLabel: UILabel!
    @IBOutlet weak var btcButton: UIButton!
    
    // Description view
    @IBOutlet weak var bothDescriptionView: UIView!
    @IBOutlet weak var bothDescriptionTextField: UITextField!
    @IBOutlet weak var bothDescriptionButton: UIButton!
    
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
    var selectedCurrency:SelectedCurrency = .satoshis
    
    override func viewDidLoad() {
        super.viewDidLoad()

        // Text field delegates
        self.bothDescriptionTextField.delegate = self
        self.bothAmountTextField.delegate = self
        self.bothAmountTextField.addDoneButton(target: self, returnaction: #selector(self.doneButtonTapped))
        
        // Set default currency to satoshis.
        self.selectSatsCurrency()
        
        // Set colors and language.
        self.setWords()
        self.changeColors()
        self.setBasicStyling()
        self.addHeader(iconLight: "iconpiggywhite", iconDark: "iconpiggyyellow", title: Language.getWord(withID: "receivebitcoin"))
        
        // Set labels
        self.addressLabel.text = ""
        Task {
            if self.coreVC!.bittrWallet.lightningChannels.getActiveChannel() == nil {
                // User has no lightning channels.
                await self.setLabels(for: .onchain)
            } else if let firstIban = self.coreVC!.bittrWallet.ibanEntities.first, !firstIban.lightningAddressUsername.isEmpty {
                // User has an LNURL.
                await self.setLabels(for: .lnurl)
            } else {
                // User has channels, but no LNURL.
                await self.setLabels(for: .bitcoinqr)
            }
        }
    }
    
    func setLabels(for type:TransactionType) async {
        
        // Gather
        let onchainAddress:String = self.getCachedOnchainAddress() ?? self.getNewOnchainAddress() ?? Language.getWord(withID: "unavailable")
        let lightningInvoice:String = await self.getZeroInvoice(enteredDescription: "") ?? Language.getWord(withID: "unavailable")
        let amountText:String = ""
        let labelText:String = ""
        let bitcoinQR:String = "bitcoin:\(onchainAddress)\(amountText)\(labelText)&lightning=\(lightningInvoice)"
        let lnurl:String = {
            if let firstIban = self.coreVC!.bittrWallet.ibanEntities.first, !firstIban.lightningAddressUsername.isEmpty {
                return firstIban.lightningAddressUsername
            } else {
                return Language.getWord(withID: "unavailable")
            }
        }()
        
        DispatchQueue.main.async {
            // Show lightning bolt.
            switch type {
            case .onchain:
                self.boltStack.alpha = 0
                self.boltStackWidth.constant = 0
            default:
                self.boltStack.alpha = 1
                self.boltStackWidth.constant = 19
            }
            
            // Set labels.
            switch type {
            case .onchain:
                self.addressTitle.text = Language.getWord(withID: "address")
                self.addressLabel.text = onchainAddress
                self.qrImageView.image = "bitcoin:\(onchainAddress)".toQRCode()
            case .lightning:
                self.addressTitle.text = Language.getWord(withID: "invoice")
                self.addressLabel.text = lightningInvoice
                self.qrImageView.image = "lightning:\(lightningInvoice)".toQRCode()
            case .bitcoinqr:
                self.addressTitle.text = Language.getWord(withID: "bitcoinqr")
                self.addressLabel.text = bitcoinQR
                self.qrImageView.image = bitcoinQR.toQRCode()
            case .lnurl:
                self.addressTitle.text = Language.getWord(withID: "url")
                self.addressLabel.text = lnurl
                self.qrImageView.image = lnurl.toQRCode()
            }
            self.qrImageView.layer.magnificationFilter = .nearest
            
        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillDisappear), name: UIResponder.keyboardWillHideNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillAppear), name: UIResponder.keyboardWillShowNotification, object: nil)
        
        /*if self.coreVC!.bittrWallet.lightningChannels.count == 0 {
            // User has no Lightning channels. Show Regular QR only.
            
            self.amountAndDescriptionStackHeight.constant = 156
            self.amountAndDescriptionStack.alpha = 1
            
            
            self.view.layoutIfNeeded()
        } else if let firstIban = self.coreVC!.bittrWallet.ibanEntities.first, !firstIban.lightningAddressUsername.isEmpty {
            
            // Show LNURL
            self.lnurlStackWidth.constant = self.switchStack.bounds.width * 0.23
            self.view.layoutIfNeeded()
            self.lnurlAddressLabel.text = firstIban.lightningAddressUsername
            self.lnurlQRCode.image = self.generateQRCode(from: firstIban.lightningAddressUsername)
            self.lnurlQRCode.layer.magnificationFilter = .nearest
            self.lnurlStack.alpha = 1
            
        }*/
    }
    
    override func viewDidAppear(_ animated: Bool) {
        self.checkContentViewHeight()
    }
    
    func checkContentViewHeight() {
        let centerViewHeight = centerView.bounds.height
        if centerView.bounds.height + 60 > contentView.bounds.height {
            NSLayoutConstraint.deactivate([self.contentViewHeight])
            self.contentViewHeight = NSLayoutConstraint(item: self.contentView, attribute: .height, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: centerViewHeight + 120)
            NSLayoutConstraint.activate([self.contentViewHeight])
            self.view.layoutIfNeeded()
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
        
        let copyingText = self.addressLabel.text
        UIPasteboard.general.string = copyingText
        self.showAlert(presentingController: self, title: Language.getWord(withID: "copied"), message: copyingText ?? "", buttons: [Language.getWord(withID: "okay")], actions: nil)
    }
    
    
    @IBAction func btcButtonTapped(_ sender: UIButton) {
        
        let actionSheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        let btcOption = UIAlertAction(title: "Bitcoin", style: .default) { (action) in
            self.selectBTCCurrency()
        }
        let satsOption = UIAlertAction(title: "Satoshis", style: .default) { (action) in
            self.selectSatsCurrency()
        }
        let bitcoinValue = self.getCorrectBitcoinValue(coreVC: self.coreVC!)
        let currencyOption = UIAlertAction(title: bitcoinValue.chosenCurrency, style: .default) { (action) in
            self.selectFiatCurrency()
        }
        let cancelAction = UIAlertAction(title: Language.getWord(withID: "cancel"), style: .cancel, handler: nil)
        actionSheet.addAction(btcOption)
        actionSheet.addAction(satsOption)
        actionSheet.addAction(currencyOption)
        actionSheet.addAction(cancelAction)
        present(actionSheet, animated: true, completion: nil)
    }
    
    @objc func selectBTCCurrency() {
        self.btcLabel.text = "BTC"
        self.selectedCurrency = .bitcoin
        self.bothAmountTextField.keyboardType = .decimalPad
    }
    
    @objc func selectSatsCurrency() {
        self.btcLabel.text = "Sats"
        self.selectedCurrency = .satoshis
        self.bothAmountTextField.keyboardType = .numberPad
    }
    
    @objc func selectFiatCurrency() {
        let currency = UserDefaults.standard.value(forKey: "currency") as? String ?? "EUR"
        self.btcLabel.text = currency
        self.selectedCurrency = .currency
        self.bothAmountTextField.keyboardType = .decimalPad
    }
    
    @objc func doneButtonTapped() {
        self.view.endEditing(true)
        self.bothAmountButton.alpha = 1
        self.bothDescriptionButton.alpha = 1
        //self.resetQRs(resetAddress: false)
    }
    
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        self.doneButtonTapped()
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
        self.view.endEditing(true)
    }
    
    /*@IBAction func switchQuestionTapped(_ sender: UIButton) {
        self.view.endEditing(true)
        
        self.showAlert(presentingController: self, title: Language.getWord(withID: "transactiontype"), message: Language.getWord(withID: "transactiontype2"), buttons: [Language.getWord(withID: "okay")], actions: nil)
    }*/
    
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

enum TransactionType {
    case onchain
    case lightning
    case bitcoinqr
    case lnurl
}
