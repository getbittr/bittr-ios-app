//
//  ReceiveViewController.swift
//  bittr
//
//  Created by Tom Melters on 05/05/2023.
//

import UIKit
import CoreImage.CIFilterBuiltins
import LDKNode

class ReceiveViewController: UIViewController, UITextFieldDelegate, UIContextMenuInteractionDelegate {
    
    // Generic
    @IBOutlet weak var yellowCard: UIView!
    
    // QR view
    @IBOutlet weak var qrWhiteView: UIView!
    @IBOutlet weak var qrImageView: UIImageView!
    @IBOutlet weak var qrSpinner: UIActivityIndicatorView!
    
    // Address view
    @IBOutlet weak var addressView: UIView!
    @IBOutlet weak var addressViewButton: UIButton!
    @IBOutlet weak var boltStack: UIView!
    @IBOutlet weak var boltStackWidth: NSLayoutConstraint! // 0 or 19
    @IBOutlet weak var addressTitle: UILabel!
    @IBOutlet weak var addressLabel: UILabel!
    @IBOutlet weak var cardsStack: UIView!
    @IBOutlet weak var iconQuestion: UIImageView!
    @IBOutlet weak var questionButton: UIButton!
    
    // Lower address
    @IBOutlet weak var lowerAddressStack: UIView!
    @IBOutlet weak var lowerAddressStackHeight: NSLayoutConstraint!
    @IBOutlet weak var lowerAddressLabel: UILabel!
    
    // Copy
    @IBOutlet weak var copyIcon: UIImageView!
    @IBOutlet weak var copyLabelContainer: UIView!
    @IBOutlet weak var copyLabelContainerWidth: NSLayoutConstraint! // 0 or 40
    @IBOutlet weak var copyLabel: UILabel!
    @IBOutlet weak var copyCard: UIView!
    @IBOutlet weak var copyCardWidth: NSLayoutConstraint!
    @IBOutlet weak var copyButton: UIButton!
    
    // Refresh
    @IBOutlet weak var refreshStack: UIView!
    @IBOutlet weak var refreshStackWidth: NSLayoutConstraint!
    @IBOutlet weak var refreshCard: UIView!
    @IBOutlet weak var refreshCardWidth: NSLayoutConstraint!
    @IBOutlet weak var refreshIcon: UIImageView!
    @IBOutlet weak var refreshLabel: UILabel!
    @IBOutlet weak var refreshButton: UIButton!
    
    // Edit
    @IBOutlet weak var editStack: UIView!
    @IBOutlet weak var editStackWidth: NSLayoutConstraint!
    @IBOutlet weak var editCard: UIView!
    @IBOutlet weak var editCardWidth: NSLayoutConstraint!
    @IBOutlet weak var editButton: UIButton!
    @IBOutlet weak var editIcon: UIImageView!
    @IBOutlet weak var editLabel: UILabel!
    
    // More
    @IBOutlet weak var moreStack: UIView!
    @IBOutlet weak var moreStackWidth: NSLayoutConstraint!
    @IBOutlet weak var moreCard: UIView!
    @IBOutlet weak var moreCardWidth: NSLayoutConstraint!
    @IBOutlet weak var moreButton: UIButton!
    @IBOutlet weak var moreIcon: UIImageView!
    @IBOutlet weak var moreLabel: UILabel!
    
    // Main scroll view
    @IBOutlet weak var scrollView: UIScrollView!
    @IBOutlet weak var scrollViewTrailing: NSLayoutConstraint!
    @IBOutlet weak var scrollViewBottom: NSLayoutConstraint!
    @IBOutlet weak var contentView: UIView!
    @IBOutlet weak var contentViewHeight: NSLayoutConstraint!
    @IBOutlet weak var centerView: UIView!
    @IBOutlet weak var contentBackgroundButton: UIButton!
    
    // Amount view
    @IBOutlet weak var amountStack: UIView!
    @IBOutlet weak var amountStackHeight: NSLayoutConstraint!
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
    @IBOutlet weak var descriptionStack: UIView!
    @IBOutlet weak var descriptionStackHeight: NSLayoutConstraint! // 0 or 55
    
    // Variables
    var coreVC:CoreViewController?
    var homeVC:HomeViewController?
    
    // Type
    var currentType:TransactionType = .onchain
    var currentCopyableText = ""
    
    var keyboardIsActive = false
    var maximumReceivableLNSats:Int?
    var completedTransaction:Transaction?
    var pendingLightningInvoice = ""
    var didDoublecheckLastUsedAddress = false
    var selectedCurrency:SelectedCurrency = .satoshis
    
    override func viewDidLoad() {
        super.viewDidLoad()

        // Text field delegates
        self.bothDescriptionTextField.delegate = self
        self.bothAmountTextField.delegate = self
        self.bothAmountTextField.addDoneButton(target: self, returnaction: #selector(self.doneButtonTapped))
        
        // QR code. UIImageView defaults to isUserInteractionEnabled = false, so
        // the long-press context menu (Copy / Share) below never received touches
        // without this — enable it so the interaction actually fires.
        self.qrImageView.isUserInteractionEnabled = true
        self.qrImageView.addInteraction(UIContextMenuInteraction(delegate: self))
        
        // Set default currency to satoshis.
        self.selectSatsCurrency()
        
        self.addressTitle.accessibilityIdentifier = TestID.Receive.addressTitle
        self.addressLabel.accessibilityIdentifier = TestID.Receive.addressLabel
        self.lowerAddressLabel.accessibilityIdentifier = TestID.Receive.invoiceLabel
        self.qrImageView.accessibilityIdentifier = TestID.Receive.qrImageView
        self.qrSpinner.accessibilityIdentifier = TestID.Receive.qrSpinner
        self.questionButton.accessibilityIdentifier = TestID.Receive.questionButton
        self.bothAmountTextField.accessibilityIdentifier = TestID.Receive.amountTextField
        self.btcButton.accessibilityIdentifier = TestID.Receive.currencyButton
        self.btcLabel.accessibilityIdentifier = TestID.Receive.currencyLabel
        self.copyButton.accessibilityIdentifier = TestID.Receive.copyButton
        self.refreshButton.accessibilityIdentifier = TestID.Receive.refreshButton
        self.editButton.accessibilityIdentifier = TestID.Receive.editButton
        self.moreButton.accessibilityIdentifier = TestID.Receive.moreButton

        // Set colors and language.
        self.setWords()
        self.changeColors()
        self.setBasicStyling()
        self.addHeader(iconLight: "iconpiggywhite", iconDark: "iconpiggyyellow", title: Language.getWord(withID: "receivebitcoin"))
        
        // Set labels
        self.cardsStack.alpha = 0
        if !self.lightningIsAvailable() {
            // User has no lightning channels.
            self.alertTapped(for: .onchain, withoutAnimation: true)
        } else if self.userLNURL() != nil {
            // User has an LNURL.
            self.alertTapped(for: .lnurl, withoutAnimation: true)
        } else {
            // User has channels, but no LNURL.
            self.alertTapped(for: .bitcoinqr, withoutAnimation: true)
        }
    }
    
    func setLabels(for type:TransactionType, newAddress:Bool = false) async {
        DispatchQueue.main.async {
            self.updateCards(for: type)
            self.currentType = type
        }
        
        // Gather
        let onchainAddress:String = {
            if type == .onchain || type == .bitcoinqr {
                if newAddress {
                    let nextUnusedAddress = BitcoinManager.shared.bittrWallet.onchainAddresses?.getNextUnusedAddress()
                    if nextUnusedAddress == nil {
                        self.showAlert(presentingController: self, title: Language.getWord(withID: "address"), message: Language.getWord(withID: "noaddressavailable"), buttons: [Language.getWord(withID: "okay")], actions: nil)
                    }
                    return nextUnusedAddress ?? self.getCachedOnchainAddress() ?? Language.getWord(withID: "unavailable")
                } else {
                    return self.getCachedOnchainAddress() ?? Language.getWord(withID: "unavailable")
                }
            } else {
                return ""
            }
        }()
        
        let enteredDescription = (self.bothDescriptionTextField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
        
        // Read the entered amount once, as whole satoshis, and derive everything else from it.
        let amountInSatoshis:Int? = {
            let enteredAmount = (self.bothAmountTextField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !enteredAmount.isEmpty else {
                // No amount has been entered. Create a zero invoice.
                return nil
            }
            
            // An amount has been entered. Convert the selected currency to satoshis.
            switch self.selectedCurrency {
            case .satoshis:
                return enteredAmount.parsedUserAmount(allowingFraction: false)?.satoshis()
            case .bitcoin:
                return enteredAmount.parsedUserAmount()?.satoshisFromBitcoin()
            case .currency:
                let bitcoinValue = BitcoinManager.shared.bittrWallet.getCorrectBitcoinValue()
                let rate = Decimal(Double(bitcoinValue.currentValue))
                guard let fiatAmount = enteredAmount.parsedUserAmount(), rate > 0 else {
                    Log.info("Could not read the entered amount.")
                    return nil
                }
                return (fiatAmount / rate).satoshisFromBitcoin()
            }
        }()
        let amountInBTC:CGFloat? = amountInSatoshis.map { $0.inBTC() }
        
        let lightningInvoice:String = await {
            guard !(type == .onchain || type == .lnurl) else {
                return nil
            }
            
            guard let amountInSatoshis = amountInSatoshis, amountInSatoshis > 0 else {
                return await self.getZeroInvoice(enteredDescription: enteredDescription)
            }
            return await self.getRegularInvoice(amountMsat: UInt64(amountInSatoshis) * 1_000, description: enteredDescription, expirySecs: 3600)
        }() ?? Language.getWord(withID: "unavailable")
        
        var amountText:String = ""
        var labelText:String = ""
        
        if amountInBTC != nil {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.minimumFractionDigits = 0
            formatter.maximumFractionDigits = 8
            formatter.usesGroupingSeparator = false
            amountText = "?amount=\(formatter.string(from: amountInBTC! as NSNumber)!)".replacingOccurrences(of: ",", with: ".")
        }
        if enteredDescription != "" {
            labelText = "&label=\(enteredDescription)"
        }
        
        let bitcoinQR:String = "bitcoin:\(onchainAddress)\(amountText)\(labelText)&lightning=\(lightningInvoice)"
        
        let userLightningURL = self.userLNURL()
        let lnurl = userLightningURL ?? Language.getWord(withID: "unavailable")
        
        DispatchQueue.main.async {
            
            // Show lightning bolt.
            switch type {
            case .onchain:
                self.boltStack.alpha = 0
                self.boltStackWidth.constant = 0
            case .bitcoinqr:
                self.boltStack.alpha = 0
                self.boltStackWidth.constant = 0
            default:
                self.boltStack.alpha = 1
                self.boltStackWidth.constant = 19
            }
            
            // Set labels. Optional: an unavailable LNURL has no QR (see .lnurl).
            let qrCode:UIImage?
            switch type {
            case .onchain:
                self.addressTitle.text = Language.getWord(withID: "address")
                self.addressLabel.text = onchainAddress + amountText
                self.lowerAddressLabel.text = ""
                qrCode = "bitcoin:\(onchainAddress)\(amountText)".uppercased().toBigQRCode()!
                self.hideLowerAddress()
                self.currentCopyableText = amountText.isEmpty
                    ? onchainAddress
                    : "bitcoin:\(onchainAddress)\(amountText)"
            case .lightning:
                self.addressTitle.text = Language.getWord(withID: "invoice")
                self.addressLabel.text = ""
                self.lowerAddressLabel.text = lightningInvoice
                qrCode = "lightning:\(lightningInvoice)".uppercased().toBigQRCode()!
                self.showLowerAddress()
                self.currentCopyableText = lightningInvoice
            case .bitcoinqr:
                self.addressTitle.text = Language.getWord(withID: "bitcoinqr")
                self.addressLabel.text = ""
                self.lowerAddressLabel.text = bitcoinQR.replacingOccurrences(of: "?", with: "?\u{2060}")
                qrCode = bitcoinQR.toBigQRCode()!
                self.showLowerAddress()
                self.currentCopyableText = bitcoinQR
            case .lnurl:
                self.addressTitle.text = Language.getWord(withID: "url")
                self.addressLabel.text = lnurl
                self.lowerAddressLabel.text = ""
                // Don't build a QR for an unavailable address — it would encode
                // the literal word "Unavailable". Leave it empty in that case.
                qrCode = userLightningURL != nil ? lnurl.toBigQRCode() : nil
                self.hideLowerAddress()
                self.currentCopyableText = lnurl
            }

            self.qrImageView.image = qrCode

            // Hide the QR view entirely when there's nothing to encode.
            self.qrImageView.alpha = qrCode != nil ? 1 : 0
            self.addressLabel.alpha = 1
            self.lowerAddressLabel.alpha = 1
            self.addressTitle.alpha = 1
            self.iconQuestion.alpha = 1
            self.qrSpinner.stopAnimating()
        }
    }
    
    func updateCards(for type:TransactionType) {
        
        // Cards stack width
        let cardsStackWidth = UIScreen.main.bounds.width - 60
        let paddingDistance:CGFloat = 12
        // Number of cards
        var numberOfCards:CGFloat = 0
        var refreshIsVisible = false
        var editIsVisible = false
        var moreIsVisible = false
        var copyLabelIsVisible = true
        
        switch type {
        case .onchain:
            refreshIsVisible = true
            editIsVisible = true
            copyLabelIsVisible = false
            if BitcoinManager.shared.bittrWallet.lightningChannels.getActiveChannel() == nil {
                // User has no lightning channels.
                numberOfCards = 3
                moreIsVisible = false
            } else {
                numberOfCards = 4
                moreIsVisible = true
            }
        case .lightning:
            numberOfCards = 3
            refreshIsVisible = false
            copyLabelIsVisible = true
            moreIsVisible = true
            editIsVisible = true
        case .bitcoinqr:
            numberOfCards = 3
            refreshIsVisible = false
            copyLabelIsVisible = true
            moreIsVisible = true
            editIsVisible = true
        case .lnurl:
            numberOfCards = 2
            refreshIsVisible = false
            copyLabelIsVisible = true
            moreIsVisible = true
            editIsVisible = false
        }
        
        if copyLabelIsVisible {
            self.copyLabelContainer.alpha = 1
            self.copyLabelContainerWidth.constant = 40
        } else {
            self.copyLabelContainer.alpha = 0
            self.copyLabelContainerWidth.constant = 0
        }
        
        let cardWidth:CGFloat = {
            if copyLabelIsVisible {
                return (cardsStackWidth - (paddingDistance*(numberOfCards-1))) / numberOfCards
            } else {
                return ((cardsStackWidth - 35) - (paddingDistance*(numberOfCards-1))) / (numberOfCards - 1)
            }
        }()
        
        self.copyCardWidth.constant = {
            if copyLabelIsVisible {
                return editIsVisible ? (cardWidth-10) : cardWidth
            } else {
                return 35
            }
        }()
        
        if refreshIsVisible {
            self.refreshStack.alpha = 1
            if moreIsVisible {
                self.refreshStackWidth.constant = (cardWidth - 10) + paddingDistance
                self.refreshCardWidth.constant = (cardWidth - 10)
            } else {
                self.refreshStackWidth.constant = (cardWidth - 22) + paddingDistance
                self.refreshCardWidth.constant = (cardWidth - 22)
            }
        } else {
            self.refreshStack.alpha = 0
            self.refreshStackWidth.constant = 0
        }
        
        if editIsVisible {
            self.editStack.alpha = 1
            self.editStackWidth.constant = (cardWidth+22) + paddingDistance
            self.editCardWidth.constant = cardWidth+22
        } else {
            self.editStack.alpha = 0
            self.editStackWidth.constant = 0
            self.editCardWidth.constant = 0
        }
        
        if moreIsVisible {
            self.moreStack.alpha = 1
            self.moreStackWidth.constant = (editIsVisible ? (cardWidth-12) : cardWidth) + paddingDistance
            self.moreCardWidth.constant = editIsVisible ? (cardWidth-12) : cardWidth
        } else {
            self.moreStack.alpha = 0
            self.moreStackWidth.constant = 0
            self.moreCardWidth.constant = 0
        }
        
        self.view.layoutIfNeeded()
        self.cardsStack.alpha = 1
    }
    
    @IBAction func copyTapped(_ sender: UIButton) {
        let copyingText = self.currentCopyableText
        UIPasteboard.general.string = copyingText
        self.showAlert(presentingController: self, title: Language.getWord(withID: "copied"), message: copyingText, buttons: [Language.getWord(withID: "okay")], actions: nil)
    }
    
    @IBAction func refreshTapped(_ sender: UIButton) {
        self.view.endEditing(true)
        
        self.showAlert(presentingController: self, title: Language.getWord(withID: "newaddress"), message: Language.getWord(withID: "newaddress2"), buttons: [Language.getWord(withID: "cancel"), Language.getWord(withID: "confirm")], actions: [nil, #selector(self.confirmOnchainAddress)])
    }
    
    @objc func confirmOnchainAddress() {
        self.hideAlert()
        self.alertTapped(for: .onchain, newAddress: true)
    }
    
    @IBAction func editTapped(_ sender: UIButton) {
        self.view.endEditing(true)
        if self.amountStack.alpha == 1 {
            self.hideAmountStack()
        } else {
            self.showAmountStack()
        }
    }
    
    @IBAction func moreTapped(_ sender: UIButton) {
        self.view.endEditing(true)
        
        self.showAlert(presentingController: self, title: Language.getWord(withID: "transactiontype"), message: Language.getWord(withID: "selecttransactiontype"), buttons: [Language.getWord(withID: "cancel"), Language.getWord(withID: "getaddress"), Language.getWord(withID: "getbitcoinqr"), Language.getWord(withID: "createinvoice"), Language.getWord(withID: "showlnurl")], actions: [nil, #selector(self.tappedOnchain), #selector(self.tappedBitcoinqr), #selector(self.tappedLightning), #selector(self.tappedLnurl)])
    }
    
    @objc func tappedOnchain() {
        self.hideAlert()
        self.alertTapped(for: .onchain)
    }
    
    @objc func tappedLightning() {
        self.hideAlert()
        self.alertTapped(for: .lightning)
    }
    
    @objc func tappedBitcoinqr() {
        self.hideAlert()
        self.alertTapped(for: .bitcoinqr)
    }
    
    @objc func tappedLnurl() {
        self.hideAlert()
        self.alertTapped(for: .lnurl)
    }
    
    func alertTapped(for type:TransactionType, withoutAnimation:Bool = false, newAddress:Bool = false) {
        
        if type != self.currentType {
            self.hideAmountStack()
        }
        self.qrImageView.alpha = 0
        self.addressLabel.alpha = 0
        self.addressTitle.alpha = 0
        self.lowerAddressLabel.alpha = 0
        self.boltStack.alpha = 0
        self.iconQuestion.alpha = 0
        self.qrSpinner.startAnimating()
        
        // Wait for onchain address management to finish before showing the onchain
        // address — manageOnchainAddresses() calls onchainAddressesReady() when it
        // sets onchainAddressesVerified, which re-enters this method.
        if (type == .onchain || type == .bitcoinqr) && !newAddress && BitcoinManager.shared.bittrWallet.onchainAddressesVerified == false {
            self.currentType = type
            self.updateCards(for: type)
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
                guard let self = self,
                      BitcoinManager.shared.bittrWallet.onchainAddressesVerified == false,
                      self.currentType == .onchain || self.currentType == .bitcoinqr else { return }
                Log.info("Onchain address verification timed out — showing best-available address.")
                BitcoinManager.shared.bittrWallet.onchainAddressesVerified = true
                self.alertTapped(for: self.currentType, withoutAnimation: true)
            }
            return
        }

        let delay:Double = withoutAnimation ? 0 : 0.7
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            Task { await self.setLabels(for: type, newAddress: newAddress) }
        }
    }
    
    func onchainAddressesReady() {
        // Onchain address management complete.
        guard self.currentType == .onchain || self.currentType == .bitcoinqr else { return }
        self.alertTapped(for: self.currentType, withoutAnimation: true)
    }

    override func viewWillAppear(_ animated: Bool) {
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillDisappear), name: UIResponder.keyboardWillHideNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillAppear), name: UIResponder.keyboardWillShowNotification, object: nil)
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
    
    @IBAction func btcButtonTapped(_ sender: UIButton) {
        
        let actionSheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        let btcOption = UIAlertAction(title: "Bitcoin", style: .default) { (action) in
            self.selectBTCCurrency()
        }
        let satsOption = UIAlertAction(title: "Satoshis", style: .default) { (action) in
            self.selectSatsCurrency()
        }
        let bitcoinValue = BitcoinManager.shared.bittrWallet.getCorrectBitcoinValue()
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
        self.alertTapped(for: self.currentType)
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
    
    @IBAction func questionButtonTapped(_ sender: UIButton) {
        self.view.endEditing(true)
        
        var title = ""
        var message = ""
        
        switch self.currentType {
        case .onchain:
            title = Language.getWord(withID: "address")
            message = Language.getWord(withID: "alertmessageonchain")
        case .lightning:
            title = Language.getWord(withID: "invoice")
            message = Language.getWord(withID: "alertmessagelightning")
        case .bitcoinqr:
            title = Language.getWord(withID: "bitcoinqr")
            message = Language.getWord(withID: "alertmessagebitcoinqr")
        case .lnurl:
            title = Language.getWord(withID: "alertlnurl")
            message = Language.getWord(withID: "alertmessagelnurl")
        }
        
        self.showAlert(presentingController: self, title: title, message: message, buttons: [Language.getWord(withID: "okay")], actions: nil)
    }
    
    func lightningIsAvailable() -> Bool {
        if BitcoinManager.shared.bittrWallet.lightningChannels.getActiveChannel() == nil {
            return false
        } else {
            return true
        }
    }
    
    func userLNURL() -> String? {
        // Return the first iban entity that actually has a lightning address.
        // Checking only `.first` missed it when the lightning-address iban
        // wasn't first after parseDevice's sort (e.g. multiple deposit codes).
        for iban in BitcoinManager.shared.bittrWallet.ibanEntities where !iban.lightningAddressUsername.isEmpty {
            return iban.lightningAddressUsername
        }
        return nil
    }
    
    func showLowerAddress() {
        NSLayoutConstraint.deactivate([self.lowerAddressStackHeight])
        self.lowerAddressStackHeight = NSLayoutConstraint(item: self.lowerAddressStack, attribute: .height, relatedBy: .greaterThanOrEqual, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 0)
        NSLayoutConstraint.activate([self.lowerAddressStackHeight])
        self.lowerAddressStack.alpha = 1
        self.view.layoutIfNeeded()
    }
    
    func hideLowerAddress() {
        NSLayoutConstraint.deactivate([self.lowerAddressStackHeight])
        self.lowerAddressStackHeight = NSLayoutConstraint(item: self.lowerAddressStack, attribute: .height, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 0)
        NSLayoutConstraint.activate([self.lowerAddressStackHeight])
        self.lowerAddressStack.alpha = 0
        self.view.layoutIfNeeded()
    }
    
    func showAmountStack() {
        UIView.animate(withDuration: 0.25, delay: 0, options: .curveEaseInOut) {
            if self.currentType == .onchain {
                self.descriptionStack.alpha = 0
                self.descriptionStackHeight.constant = 0
            } else {
                self.descriptionStack.alpha = 1
                self.descriptionStackHeight.constant = 55
            }
            NSLayoutConstraint.deactivate([self.amountStackHeight])
            self.amountStackHeight = NSLayoutConstraint(item: self.amountStack, attribute: .height, relatedBy: .greaterThanOrEqual, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 0)
            NSLayoutConstraint.activate([self.amountStackHeight])
            self.amountStack.alpha = 1
            self.view.layoutIfNeeded()
        } completion: { _ in
            self.checkContentViewHeight()
        }
    }
    
    func hideAmountStack() {
        self.bothAmountTextField.text = ""
        self.bothDescriptionTextField.text = ""
        UIView.animate(withDuration: 0.25, delay: 0, options: .curveEaseInOut) {
            NSLayoutConstraint.deactivate([self.amountStackHeight])
            self.amountStackHeight = NSLayoutConstraint(item: self.amountStack, attribute: .height, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 0)
            NSLayoutConstraint.activate([self.amountStackHeight])
            self.amountStack.alpha = 0
            self.view.layoutIfNeeded()
        } completion: { _ in
            self.checkContentViewHeight()
        }
    }
    
    func contextMenuInteraction(_ interaction: UIContextMenuInteraction, configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration? {
                
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in
            
            let copyAction = UIAction(title: "Copy", image: UIImage(systemName: "doc.on.doc")) { _ in
                self.copyTapped(self.copyButton)
            }
            
            let shareAction = UIAction(title: "Share", image: UIImage(systemName: "square.and.arrow.up")) { _ in
                let items: [Any] = [self.currentCopyableText, (self.qrImageView.image as Any)].compactMap { $0 }
                let vc = UIActivityViewController(activityItems: items, applicationActivities: nil)
                self.present(vc, animated: true)
            }
            
            return UIMenu(title: "", children: [copyAction, shareAction])
        }
    }
}

enum TransactionType {
    case onchain
    case lightning
    case bitcoinqr
    case lnurl
}
