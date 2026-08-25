//
//  SendViewController.swift
//  bittr
//
//  Created by Tom Melters on 05/05/2023.
//

import UIKit
import LDKNode
import LightningDevKit

class SendViewController: UIViewController, UITextFieldDelegate, OnchainSyncFailureReporting {
    
    // Generic
    @IBOutlet weak var yellowCard: UIView!
    @IBOutlet weak var scrollView: UIScrollView!
    @IBOutlet weak var scrollViewTrailing: NSLayoutConstraint!
    @IBOutlet weak var scrollViewBottom: NSLayoutConstraint!
    @IBOutlet weak var contentView: UIView!
    @IBOutlet weak var contentViewHeight: NSLayoutConstraint!
    @IBOutlet weak var contentViewBottom: NSLayoutConstraint!
    @IBOutlet weak var backgroundButton: UIButton!
    @IBOutlet weak var centerView: UIView!
    @IBOutlet weak var centerBackgroundButton: UIButton!
    
    // Switch view
    @IBOutlet weak var viewRegular: UIView!
    @IBOutlet weak var viewInstant: UIView!
    @IBOutlet weak var regularButton: UIButton!
    @IBOutlet weak var instantButton: UIButton!
    @IBOutlet weak var labelRegular: UILabel!
    @IBOutlet weak var labelInstant: UILabel!
    @IBOutlet weak var iconLightning: UIImageView!
    @IBOutlet weak var switchQuestionMark: UIImageView!
    @IBOutlet weak var switchQuestionButton: UIButton!
    
    // To view
    @IBOutlet weak var toLabel: UILabel! // Address or Invoice
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
    
    // Amount view
    @IBOutlet weak var amountStack: UIView!
    @IBOutlet weak var btcView: UIView!
    @IBOutlet weak var btcLabel: UILabel!
    @IBOutlet weak var btcButton: UIButton!
    @IBOutlet weak var amountView: UIView! // Background
    @IBOutlet weak var amountTextField: UITextField!
    @IBOutlet weak var amountButton: UIButton!
    @IBOutlet weak var availableAmount: UILabel!
    @IBOutlet weak var questionCircle: UIImageView!
    @IBOutlet weak var availableButton: UIButton!
    @IBOutlet weak var availableQuestionButton: UIButton!
    @IBOutlet weak var bdkSpinner: UIActivityIndicatorView!
    
    // Main scroll - Next button
    @IBOutlet weak var nextView: UIView! // Background
    @IBOutlet weak var nextSpinner: UIActivityIndicatorView!
    @IBOutlet weak var nextLabel: UILabel! // Next or Manual input
    @IBOutlet weak var nextButton: UIButton!
    @IBOutlet weak var arrowIconWidth: NSLayoutConstraint!
    @IBOutlet weak var arrowIconLeading: NSLayoutConstraint!
    @IBOutlet weak var arrowIcon: UIImageView!
    
    // Confirm view
    @IBOutlet weak var confirmContainer: UIView!
    
    // Variables
    var coreVC:CoreViewController?
    var maximumSendableOnchainSats:Int?
    var didTapAvailable = false // User has tapped the maximum available onchain amount.
    var isSendingMaximum = false // User intends to empty their onchain funds.
    // Drain amount + its fee, so the confirm screen can restate the amount when
    // the user switches fee rate — a drain is whatever is left after the fee.
    var drainTotalSats:Int?
    var completedTransaction:Transaction?
    var bitcoinQR = ""
    var pendingLightningInvoice = ""
    var pendingOnchainAddress = ""
    var pendingOnchainAmount:Int = 0
    
    // Pending URI data from segue
    var pendingBitcoinURI: (address: String, amount: String, label: String)?
    var pendingLightningURI: String?
    
    // Pending LNURL data
    var pendingLNURLCallback: String?
    var pendingLNURLDescription: String?
    var pendingLNURLMinAmount: Int?
    var pendingLNURLMaxAmount: Int?
    
    // LNURL Withdraw request properties
    var pendingWithdrawCallback: String?
    var pendingWithdrawK1: String?
    var pendingWithdrawMinAmount: Int?
    var pendingWithdrawMaxAmount: Int?
    
    // LNURL Pay request properties
    var pendingLnurlInvoice:String?
    var pendingLnurlNote:String?
    
    // LNURL Auth
    var pendingLnurlAuth: LNURLAuthRequest?
    
    // User selected variables
    var selectedCurrency:SelectedCurrency = .satoshis
    var onchainOrLightning:OnchainOrLightning = .lightning
    
    // Confirm variables
    var confirmSendVC:ConfirmSendViewController?
    var confirmSatoshis:Int = 0
    var confirmAddress = ""
    var confirmLnurlEmail:String?
    var feePerVbLow:Double = 0
    var feePerVbMedium:Double = 0
    var feePerVbHigh:Double = 0
    var confirmTxSize:Double = 0
    var confirmLightningFees:Int = 0
    
    override func viewDidLoad() {
        super.viewDidLoad()

        // Set colors and language
        self.changeColors()
        self.setWords()
        self.setBasicStyling()
        self.addHeader(iconLight: "iconpiggywhite", iconDark: "iconpiggyyellow", title: Language.getWord(withID: "sendbitcoin"))
        
        // Set default currency to satoshis
        self.btcLabel.text = "Sats"
        
        // Initialize UI and set Send All.
        self.updateLabels()
        
        // Handle pending URI data from segue.
        self.checkForPendingURI()
    }
    
    func setSendAllLabel() {
        
        if self.onchainOrLightning == .onchain {
            // Set "Send all" for onchain transactions.
            
            if BitcoinManager.shared.bdkWallet == nil || !BitcoinManager.shared.bdkWalletHasBeenScanned || BitcoinManager.shared.bdkWalletIsScanning {
                Log.info("BDK wallet isn't available yet.")
                self.bdkWalletUnavailable()
            } else {
                Log.info("BDK wallet is available.")
                
                // Ensure current fee rates have been fetched.
                guard self.feePerVbMedium > 0 else {
                    self.bdkSpinner.startAnimating()
                    Task { await self.fetchFeeEstimatesThenSetSendAllLabel() }
                    return
                }
                
                // Calculate maximum sendable onchain amount.
                // Minimum 0 satoshis. Minimum 1 sat/Vbyte.
                self.bdkSpinner.startAnimating()
                let satPerVb = self.feePerVbMedium.wholeSatPerVb
                DispatchQueue.global(qos: .userInitiated).async {
                    let sendable = self.getMaximumSendableSats(satPerVb: satPerVb)
                        ?? max(BitcoinManager.shared.bittrWallet.satoshisOnchainSpendable ?? 0, 0)
                    
                    DispatchQueue.main.async {
                        self.bdkSpinner.stopAnimating()
                        self.maximumSendableOnchainSats = sendable
                        self.availableAmount.text = Language.getWord(withID:"youcansend").replacingOccurrences(of: "<amount>", with: "\(sendable)".addSpaces())
                    }
                }
            }
        } else {
            // Set "Send all" for lightning payments.
            self.bdkSpinner.stopAnimating()
            let lightningSats = (BitcoinManager.shared.bittrWallet.lightningChannels.getActiveChannel()?.outboundCapacityMsat ?? 0)/1000
            self.availableAmount.text = Language.getWord(withID:"youcansend").replacingOccurrences(of: "<amount>", with: "\(lightningSats)".addSpaces())
        }
    }
    
    func fetchFeeEstimatesThenSetSendAllLabel() async {
        Log.info("Will download fee estimates.")
        
        let feeEstimates = await BitcoinManager.shared.getFeeEstimates()
        
        await MainActor.run {
            self.bdkSpinner.stopAnimating()
            
            guard let feeEstimates else {
                Log.info("Could not fetch recommended fees; quoting the spendable balance instead.")
                let spendable = max(BitcoinManager.shared.bittrWallet.satoshisOnchainSpendable ?? 0, 0)
                self.availableAmount.text = Language.getWord(withID:"youcansend").replacingOccurrences(of: "<amount>", with: "\(spendable)".addSpaces())
                return
            }
            
            self.feePerVbLow = feeEstimates.economy
            self.feePerVbMedium = feeEstimates.hour
            self.feePerVbHigh = feeEstimates.fastest
            
            self.setSendAllLabel()
        }
    }
    
    func bdkWalletUnavailable() {
        
        // Show alert.
        self.availableAmount.text = Language.getWord(withID:"youcansend").replacingOccurrences(of: "<amount>", with: "0")
        self.bdkSpinner.startAnimating()
        self.showAlert(title: Language.getWord(withID: "syncing"), message: Language.getWord(withID: "awaitingbdksync"), buttons: [.dismiss(Language.getWord(withID: "okay"))])
        
        // Check whether BDK wallet is currently scanning.
        if !BitcoinManager.shared.bdkWalletIsScanning {
            Log.info("BDK wallet isn't scanning. Will start scan.")

            // didStartBDK is synchronous and blocking (descriptor derivation,
            // SQLite connection, electrum client setup), so run it off main
            // and hop back for the UI outcomes. didSyncBdkWallet manages its
            // own threading and completes on main.
            DispatchQueue.global(qos: .userInitiated).async {
                let didStartBDK = BitcoinManager.shared.didStartBDK()
                DispatchQueue.main.async {
                    if didStartBDK {
                        Log.info("Did start BDK.")

                        BitcoinManager.shared.didSyncBdkWallet { hasBeenSynced in
                            if hasBeenSynced {
                                Log.info("Did scan BDK wallet.")
                                self.setSendAllLabel()
                            } else {
                                Log.info("Could not scan BDK wallet.")
                                self.presentOnchainSyncFailedAlert()
                            }
                        }
                    } else {
                        Log.info("Could not start BDK.")
                        self.presentOnchainSyncFailedAlert()
                    }
                }
            }
        } else {
            Log.info("Waiting for BDK wallet to finish scanning.")
        }
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
        if self.amountTextField.isFirstResponder {
            // Move to next step
            self.amountTextField.resignFirstResponder()
            self.nextButtonTapped(self.nextButton)
        }
    }
    
    func selectCurrency(_ type:SelectedCurrency) {
        switch type {
        case .bitcoin: self.btcLabel.text = "BTC"
        case .satoshis: self.btcLabel.text = "Sats"
        case .currency:
            let currency = CacheStore.value(for: CacheKeys.currency) ?? "EUR"
            self.btcLabel.text = currency
        }
        self.selectedCurrency = type
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
        let currency = CacheStore.value(for: CacheKeys.currency) ?? "EUR"
        self.btcLabel.text = currency
        self.selectedCurrency = .currency
    }
    
    @IBAction func availableButtonTapped(_ sender: UIButton) {
        
        if self.onchainOrLightning == .onchain {
            // Regular - use satoshis for onchain too
            let sendableInSatoshis:Int = self.maximumSendableOnchainSats ?? max(BitcoinManager.shared.bittrWallet.satoshisOnchainSpendable ?? 0, 0)
            self.amountTextField.text = "\(sendableInSatoshis)"
            self.btcLabel.text = "Sats"
            self.selectedCurrency = .satoshis
            self.didTapAvailable = true
        } else {
            // Instant
            let sendableInSatoshis:Int = Int((BitcoinManager.shared.bittrWallet.lightningChannels.getActiveChannel()?.outboundCapacityMsat ?? 0)/1000)
            self.amountTextField.text = "\(sendableInSatoshis)"
            self.btcLabel.text = "Sats"
            self.selectedCurrency = .satoshis
        }
    }
    
    @IBAction func toPasteButtonTapped(_ sender: UIButton) {
        self.view.endEditing(true)
        if let actualString = UIPasteboard.general.string {
            self.handleScannedOrPastedString(actualString)
        }
    }
    
    @IBAction func qrButtonTapped(_ sender: UIButton) {
        self.view.endEditing(true)
        self.performSegue(withIdentifier: "SendToScanner", sender: self)
    }
    
    @IBAction func backgroundButtonTapped(_ sender: UIButton) {
        self.view.endEditing(true)
    }
    
    @IBAction func nextButtonTapped(_ sender: UIButton) {
        self.view.endEditing(true)
        
        // Check if we have pending LNURL data FIRST (for when Next button shows "Done")
        if self.pendingLNURLCallback != nil, self.pendingLNURLMinAmount != nil, self.pendingLNURLMaxAmount != nil {
            self.handleLNURLAmountCompletion()
            return
        }
        
        // Check if we have pending withdraw request data
        if self.pendingWithdrawCallback != nil, self.pendingWithdrawMinAmount != nil, self.pendingWithdrawMaxAmount != nil {
            self.handleWithdrawAmountCompletion()
            return
        }
        
        if self.onchainOrLightning == .onchain {
            if BitcoinManager.shared.bdkWallet == nil || !BitcoinManager.shared.bdkWalletHasBeenScanned || BitcoinManager.shared.bdkWalletIsScanning {
                Log.info("BDK wallet isn't available yet.")
                self.bdkWalletUnavailable()
            } else {
                // Check onchain transaction.
                self.checkSendOnchain()
            }
        } else {
            // Check lightning transaction.
            self.checkSendLightning()
        }
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        
        // Show new transaction in TransactionVC.
        if segue.identifier == "SendToTransaction" {
            if let transactionVC = segue.destination as? TransactionViewController {
                if let actualCompletedTransaction = self.completedTransaction {
                    transactionVC.tappedTransaction = actualCompletedTransaction
                    transactionVC.coreVC = self.coreVC
                }
            }
        } else if segue.identifier == "SendToSwap" {
            if let swapVC = segue.destination as? SwapViewController {
                swapVC.isFromOnchainPayment = true
                swapVC.pendingOnchainAmount = self.pendingOnchainAmount
                swapVC.pendingOnchainAddress = self.pendingOnchainAddress
                swapVC.coreVC = self.coreVC
                self.coreVC?.swapVC = swapVC
            }
        } else if segue.identifier == "SendToScanner" {
            if let scannerVC = segue.destination as? ScannerViewController {
                scannerVC.sendVC = self
            }
        }
    }
    
    
    @IBAction func switchTapped(_ sender: UIButton) {

        if (sender.boundString ?? "") == "onchain", self.bitcoinQR != "" {
            self.toTextField.text = self.bitcoinQR
            self.bitcoinQR = ""
        } else {
            // Reset fields.
            self.resetFields()
        }

        // Switch view.
        if let tag = sender.boundString {
            self.onchainOrLightning = (tag == "onchain") ? .onchain : .lightning
        }
        self.updateLabels()
    }
    
    @IBAction func btcButtonTapped(_ sender: UIButton) {
        self.view.endEditing(true)
        
        let bitcoinValue = BitcoinManager.shared.bittrWallet.getCorrectBitcoinValue()
        self.showAlert(title: Language.getWord(withID: "selectcurrency"), message: Language.getWord(withID: "selectcurrencymessage"), buttons: [.dismiss(Language.getWord(withID: "cancel")), .action("Bitcoin") { self.selectCurrency(.bitcoin) }, .action("Satoshis") { self.selectCurrency(.satoshis) }, .action(bitcoinValue.chosenCurrency) { self.selectCurrency(.currency) }])
    }
    
    @IBAction func availableQuestionTapped(_ sender: UIButton) {
        self.view.endEditing(true)
        if self.onchainOrLightning == .lightning {
            self.coreVC!.launchQuestion(question: Language.getWord(withID: "limitlightning"), answer: Language.getWord(withID: "limitlightninganswer"), type: "lightningsendable")
        } else {
            self.showAlert(title: Language.getWord(withID: "sendbitcoin"), message: Language.getWord(withID: "maximumonchain"), buttons: [.dismiss(Language.getWord(withID: "okay"))])
        }
    }
    
    @IBAction func switchQuestionTapped(_ sender: UIButton) {
        self.view.endEditing(true)
        
        self.showAlert(title: Language.getWord(withID: "transactiontype"), message: Language.getWord(withID: "transactiontype3"), buttons: [.dismiss(Language.getWord(withID: "okay"))])
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
