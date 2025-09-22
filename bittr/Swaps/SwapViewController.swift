//
//  SwapViewController.swift
//  bittr
//
//  Created by Tom Melters on 24/01/2025.
//

import UIKit
import LDKNode
import UserNotifications
import LightningDevKit

class SwapViewController: UIViewController, UITextFieldDelegate, UNUserNotificationCenterDelegate {

    // General
    @IBOutlet weak var downButton: UIButton!
    @IBOutlet weak var mainScrollView: UIScrollView!
    @IBOutlet weak var mainContentView: UIView!
    @IBOutlet weak var mainContentViewBottom: NSLayoutConstraint!
    @IBOutlet weak var contentBackground: UIButton!
    
    // Card contents
    @IBOutlet weak var centerCard: UIView!
    @IBOutlet weak var centerCardLeading: NSLayoutConstraint!
    @IBOutlet weak var centerBackground: UIButton!
    @IBOutlet weak var swapIcon: UIImageView!
    @IBOutlet weak var topLabel: UILabel!
    @IBOutlet weak var subtitleLabel: UILabel!
    @IBOutlet weak var moveLabel: UILabel!
    @IBOutlet weak var amountTextField: UITextField!
    
    // From view
    @IBOutlet weak var fromView: UIView!
    @IBOutlet weak var fromLabel: UILabel!
    @IBOutlet weak var fromButton: UIButton!
    
    // Available view
    @IBOutlet weak var availableAmountLabel: UILabel!
    @IBOutlet weak var availableButton: UIButton!
    @IBOutlet weak var questionMark: UIImageView!
    
    // Next view
    @IBOutlet weak var nextView: UIView!
    @IBOutlet weak var nextLabel: UILabel!
    @IBOutlet weak var nextButton: UIButton!
    @IBOutlet weak var nextSpinner: UIActivityIndicatorView!
    
    // Confirm card
    @IBOutlet weak var confirmCard: UIView!
    @IBOutlet weak var confirmTopLabel: UILabel!
    @IBOutlet weak var confirmTopIcon: UIImageView!
    @IBOutlet weak var confirmDirection: UIView!
    @IBOutlet weak var confirmDirectionLabel: UILabel!
    @IBOutlet weak var confirmAmount: UIView!
    @IBOutlet weak var confirmAmountLabel: UILabel!
    @IBOutlet weak var confirmFees: UIView!
    @IBOutlet weak var confirmFeesLabel: UILabel!
    @IBOutlet weak var confirmStatus: UIView!
    @IBOutlet weak var confirmStatusLabel: UILabel!
    @IBOutlet weak var resetIcon: UIImageView!
    @IBOutlet weak var confirmStatusSpinner: UIActivityIndicatorView!
    @IBOutlet weak var confirmStatusButton: UIButton!
    @IBOutlet weak var titleDirection: UILabel!
    @IBOutlet weak var titleAmount: UILabel!
    @IBOutlet weak var titleFees: UILabel!
    @IBOutlet weak var titleStatus: UILabel!
    @IBOutlet weak var statusQuestionIcon: UIImageView!
    @IBOutlet weak var statusQuestionButton: UIButton!
    
    // Download swap details
    @IBOutlet weak var downloadView: UIView!
    @IBOutlet weak var downloadButton: UIButton!
    @IBOutlet weak var downloadIcon: UIImageView!
    @IBOutlet weak var downloadLabel: UILabel!
    
    // Pending stack
    @IBOutlet weak var pendingStack: UIView!
    @IBOutlet weak var pendingStackHeight: NSLayoutConstraint! // 0 or 75
    @IBOutlet weak var pendingView: UIView!
    @IBOutlet weak var pendingButton: UIButton!
    @IBOutlet weak var pendingCoverView: UIView!
    @IBOutlet weak var pendingSpinner: UIActivityIndicatorView!
    
    // VCs
    var coreVC:CoreViewController?
    var homeVC:HomeViewController?
    
    // Swap details
    var swapDirection:SwapDirection = .onchainToLightning
    var webSocketManager:WebSocketManager?
    var isFromBackgroundNotification = false
    var isFromLightningPayment = false
    var pendingLightningInvoice = ""
    var isFromOnchainPayment = false
    var pendingOnchainAddress = ""
    var pendingOnchainAmount = 0
    var tappedSwapTransaction:Swap?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Add notification observer for swap updates
        NotificationCenter.default.addObserver(self, selector: #selector(handleSwapNotification), name: NSNotification.Name(rawValue: "swapNotification"), object: nil)
        
        // Clear any stale data if this is a manual navigation (not from payment)
        if !self.isFromLightningPayment && !self.isFromOnchainPayment && !self.isFromBackgroundNotification {
            print("DEBUG - Manual navigation to swap screen, clearing any stale data")
            self.clearPendingSwapData()
        }
        
        // Button titles
        self.downButton.setTitle("", for: .normal)
        self.centerBackground.setTitle("", for: .normal)
        self.contentBackground.setTitle("", for: .normal)
        self.nextButton.setTitle("", for: .normal)
        self.availableButton.setTitle("", for: .normal)
        self.fromButton.setTitle("", for: .normal)
        self.confirmStatusButton.setTitle("", for: .normal)
        self.pendingButton.setTitle("", for: .normal)
        self.downloadButton.setTitle("", for: .normal)
        self.statusQuestionButton.setTitle("", for: .normal)
        
        // Center card styling
        self.centerCard.layer.cornerRadius = 13
        self.centerCard.layer.shadowColor = UIColor.black.cgColor
        self.centerCard.layer.shadowOffset = CGSize(width: 0, height: 7)
        self.centerCard.layer.shadowRadius = 10.0
        self.centerCard.layer.shadowOpacity = 0.1
        
        // Confirm card styling
        self.confirmCard.layer.cornerRadius = 13
        self.confirmCard.layer.shadowColor = UIColor.black.cgColor
        self.confirmCard.layer.shadowOffset = CGSize(width: 0, height: 7)
        self.confirmCard.layer.shadowRadius = 10.0
        self.confirmCard.layer.shadowOpacity = 0.1
        self.confirmDirection.layer.cornerRadius = 8
        self.confirmAmount.layer.cornerRadius = 8
        self.confirmFees.layer.cornerRadius = 8
        self.confirmStatus.layer.cornerRadius = 8
        self.downloadView.layer.cornerRadius = 8
        
        // Amount text field
        self.amountTextField.delegate = self
        self.amountTextField.inputAccessoryView = createInputAccessoryView()
        self.amountTextField.layer.cornerRadius = 8
        self.amountTextField.layer.shadowColor = UIColor.black.cgColor
        self.amountTextField.layer.shadowOffset = CGSize(width: 0, height: 7)
        self.amountTextField.layer.shadowRadius = 10.0
        self.amountTextField.layer.shadowOpacity = 0.1
        
        // From view
        self.fromView.layer.cornerRadius = 8
        self.fromView.layer.shadowColor = UIColor.black.cgColor
        self.fromView.layer.shadowOffset = CGSize(width: 0, height: 7)
        self.fromView.layer.shadowRadius = 10.0
        self.fromView.layer.shadowOpacity = 0.1
        
        // Next view
        self.nextView.layer.cornerRadius = 13
        self.pendingView.layer.cornerRadius = 13
        
        // Available amount
        if let actualChannel = self.coreVC?.bittrWallet.bittrChannel {
            self.availableAmountLabel.text = Language.getWord(withID: "satsatatime").replacingOccurrences(of: "<amount>", with: "\(actualChannel.receivableMaximum)".addSpaces())
        } else {
            // Fallback if channel is not available
            self.availableAmountLabel.text = Language.getWord(withID: "satsatatime").replacingOccurrences(of: "<amount>", with: "0")
        }
        
        // Set colors and language
        self.changeColors()
        self.setLanguage()
        
        // Check if there's an ongoing swap and automatically show it (only if from background notification)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            print("DEBUG - SwapViewController viewDidLoad conditions:")
            print("  - isFromBackgroundNotification: \(self.isFromBackgroundNotification)")
            print("  - pendingOnchainAmount: \(self.pendingOnchainAmount)")
            print("  - isFromLightningPayment: \(self.isFromLightningPayment)")
            print("  - pendingLightningInvoice: '\(self.pendingLightningInvoice)'")
            print("  - isFromOnchainPayment: \(self.isFromOnchainPayment)")
            print("  - pendingOnchainAddress: '\(self.pendingOnchainAddress)'")
            
            if self.isFromBackgroundNotification && self.pendingOnchainAmount > 0 {
                // Handle notification-based onchain-to-lightning swap
                print("DEBUG - Calling handleNotificationSwap()")
                self.handleNotificationSwap()
            } else if self.isFromBackgroundNotification {
                print("DEBUG - Calling checkForOngoingSwap()")
                self.checkForOngoingSwap()
            } else if self.isFromLightningPayment && !self.pendingLightningInvoice.isEmpty {
                // Handle pending Lightning invoice
                self.handlePendingLightningInvoice()
            } else if self.isFromOnchainPayment && !self.pendingOnchainAddress.isEmpty {
                // Handle pending onchain payment
                self.handlePendingOnchainPayment()
            } else if self.tappedSwapTransaction != nil {
                // Show swap opened from TransactionVC.
                guard let swapDictionary = SwapManager.loadSwapDetailsFromFile(swapID: self.tappedSwapTransaction!.boltzID!) else { return }
                self.coreVC!.bittrWallet.ongoingSwap = CacheManager.dictionaryToSwap(swapDictionary)
                guard let ongoingSwap = self.coreVC!.bittrWallet.ongoingSwap else { return }
                
                self.swapDirection = ongoingSwap.swapDirection
                self.confirmDirectionLabel.text = Language.getWord(withID: "onchaintolightning")
                if ongoingSwap.swapDirection == .lightningToOnchain {
                    self.confirmDirectionLabel.text = Language.getWord(withID: "lightningtoonchain")
                }
                
                self.confirmAmountLabel.text = "\(ongoingSwap.satoshisAmount)".addSpaces() + " sats"
                let totalFees = (ongoingSwap.onchainFees ?? self.tappedSwapTransaction!.onchainFees ?? 0) + (ongoingSwap.lightningFees ?? self.tappedSwapTransaction!.lightningFees ?? 0) + (ongoingSwap.claimTransactionFee ?? 0)
                self.confirmFeesLabel.text = "\(totalFees)".addSpaces() + " sats"
                self.confirmStatusSpinner.startAnimating()
                self.confirmStatusLabel.text = "Checking"
                self.switchView("confirm")
                SwapManager.checkSwapStatus(ongoingSwap.boltzID!) { dictionary in
                    DispatchQueue.main.async {
                        self.confirmStatusLabel.alpha = 1
                        self.confirmStatusSpinner.stopAnimating()
                        if dictionary != nil, let receivedStatus = dictionary!["status"] as? String {
                            self.receivedStatusUpdate(status: receivedStatus, fullMessage: dictionary! as! [String : Any])
                        } else {
                            print("No status received.")
                        }
                    }
                }
            }
        }
        
        print("DEBUG - SwapViewController loaded. pendingOnchainAddress: \(self.pendingOnchainAddress), pendingOnchainAmount: \(self.pendingOnchainAmount)")
    }
    
    override func viewWillAppear(_ animated: Bool) {
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillDisappear), name: UIResponder.keyboardWillHideNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillAppear), name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(changeColors), name: NSNotification.Name(rawValue: "changecolors"), object: nil)
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        NotificationCenter.default.removeObserver(self)
        
        // Clear swap state when leaving the swap screen
        // This ensures that if user swipes away the page, swap data is cleared
        print("DEBUG - Leaving SwapViewController, clearing swap state")
        self.clearPendingSwapData()
    }
    
    @objc func keyboardWillDisappear() {
        
        NSLayoutConstraint.deactivate([self.mainContentViewBottom])
        self.mainContentViewBottom = NSLayoutConstraint(item: self.mainContentView!, attribute: .bottom, relatedBy: .equal, toItem: self.mainScrollView, attribute: .bottom, multiplier: 1, constant: 0)
        NSLayoutConstraint.activate([self.mainContentViewBottom])
        self.view.layoutIfNeeded()
    }
    
    @objc func keyboardWillAppear(_ notification:Notification) {
        
        if let keyboardSize = (notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue {
            
            let keyboardHeight = keyboardSize.height
            
            NSLayoutConstraint.deactivate([self.mainContentViewBottom])
            self.mainContentViewBottom = NSLayoutConstraint(item: self.mainContentView!, attribute: .bottom, relatedBy: .equal, toItem: self.mainScrollView, attribute: .bottom, multiplier: 1, constant: -keyboardHeight)
            NSLayoutConstraint.activate([self.mainContentViewBottom])
            
            self.view.layoutIfNeeded()
        }
    }
    
    @IBAction func downButtonTapped(_ sender: UIButton) {
        self.view.endEditing(true)
        self.dismiss(animated: true)
    }
    
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        self.view.endEditing(true)
        return false
    }
    
    @IBAction func fromButtonTapped(_ sender: UIButton) {
        self.view.endEditing(true)
        
        let actionSheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        let onchainToLightning = UIAlertAction(title: Language.getWord(withID: "onchaintolightning"), style: .default) { (action) in
            
            self.fromLabel.text = Language.getWord(withID: "onchaintolightning")
            self.swapDirection = .onchainToLightning
        }
        let lightningToOnchain = UIAlertAction(title: Language.getWord(withID: "lightningtoonchain"), style: .default) { (action) in
            
            self.fromLabel.text = Language.getWord(withID: "lightningtoonchain")
            self.swapDirection = .lightningToOnchain
        }
        let cancelAction = UIAlertAction(title: Language.getWord(withID: "cancel"), style: .cancel, handler: nil)
        actionSheet.addAction(onchainToLightning)
        actionSheet.addAction(lightningToOnchain)
        actionSheet.addAction(cancelAction)
        present(actionSheet, animated: true, completion: nil)
    }
    
    @IBAction func availableAmountTapped(_ sender: UIButton) {
        self.view.endEditing(true)
        
        self.coreVC!.launchQuestion(question: Language.getWord(withID: "limitlightning"), answer: Language.getWord(withID: "limitlightninganswer"), type: "lightningsendable")
    }
    
    @IBAction func nextTapped(_ sender: UIButton) {
        self.view.endEditing(true)
        
        if self.nextSpinner.isAnimating { return }
        
        let amountToBeSent = Int(self.stringToNumber(self.amountTextField.text))
        if amountToBeSent != 0 {
            let maxAmount = self.homeVC?.coreVC?.bittrWallet.bittrChannel?.receivableMaximum ?? 0
            if amountToBeSent > maxAmount {
                // You can't receive or send this much.
                self.showAlert(presentingController: self, title: Language.getWord(withID: "swapfunds2"), message: Language.getWord(withID: "swapamountexceeded").replacingOccurrences(of: "<amount>", with: "\(maxAmount)"), buttons: [Language.getWord(withID: "okay")], actions: nil)
            } else {
                self.nextLabel.alpha = 0
                self.nextSpinner.startAnimating()
                
                // Create Swap object.
                self.coreVC!.bittrWallet.ongoingSwap = Swap()
                self.coreVC!.bittrWallet.ongoingSwap!.satoshisAmount = amountToBeSent
                
                self.coreVC!.bittrWallet.ongoingSwap!.swapDirection = self.swapDirection
                Task {
                    if self.swapDirection == .onchainToLightning {
                        await SwapManager.onchainToLightning(amountMsat: UInt64(amountToBeSent*1000), swapVC: self)
                    } else {
                        await SwapManager.lightningToOnchain(amountSat: amountToBeSent, swapVC: self)
                    }
                }
            }
        } else {
            // No amount has been entered.
            self.showAlert(presentingController: self, title: Language.getWord(withID: "swapfunds2"), message: Language.getWord(withID: "enteramountofsatoshis"), buttons: [Language.getWord(withID: "okay")], actions: nil)
        }
    }
    
    @IBAction func pendingSwapTapped(_ sender: UIButton) {
        var pendingSwap = self.coreVC?.bittrWallet.ongoingSwap
        if pendingSwap == nil {
            pendingSwap = CacheManager.getLatestSwap()
        }
        if pendingSwap != nil {
            self.coreVC!.bittrWallet.ongoingSwap = pendingSwap
            self.switchView("confirm")
        }
    }
    
    func switchView(_ toView: String) {
        
        guard let centerCardLeading = self.centerCardLeading else {
            print("centerCardLeading is nil, cannot switch view")
            return
        }
        
        if toView == "confirm" {
            UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseInOut) {
                centerCardLeading.constant = 15 - self.view.bounds.width
                self.view.layoutIfNeeded()
            }
        } else {
            UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseInOut) {
                centerCardLeading.constant = 15
                self.view.layoutIfNeeded()
            }
        }
    }
    
    @IBAction func confirmStatusButtonTapped(_ sender: UIButton) {
        
        DispatchQueue.main.async {
            self.confirmStatusLabel.alpha = 0
            self.resetIcon.alpha = 0
            
            if let swapID = self.coreVC?.bittrWallet.ongoingSwap?.boltzID {
                print("🔍 Checking swap status for ID: \(swapID)")
                print("🔄 Current swap direction: \(self.swapDirection)")
                print("📊 Ongoing swap details: \(self.coreVC?.bittrWallet.ongoingSwap?.dateID ?? "nil")")
                
                SwapManager.checkSwapStatus(swapID) { dictionary in
                    DispatchQueue.main.async {
                        self.confirmStatusLabel.alpha = 1
                        self.resetIcon.alpha = 1
                        
                        print("📡 Received swap status response: \(dictionary ?? [:])")
                        
                        if dictionary != nil, let receivedStatus = dictionary!["status"] as? String {
                            print("✅ Status received: \(receivedStatus)")
                            print("🔄 Current swap direction: \(self.swapDirection)")
                            
                            self.confirmStatusLabel.text = self.userFriendlyStatus(receivedStatus: receivedStatus)
                            
                            if receivedStatus == "invoice.failedToPay" || receivedStatus == "swap.expired" || receivedStatus == "transaction.lockupFailed" {
                                print("❌ Swap failed with status: \(receivedStatus)")
                                //TODO RUBEN: Add refund logic here
                            } else if receivedStatus == "transaction.confirmed" || receivedStatus == "invoice.settled" {
                                print("✅ Transaction confirmed!")
                                print("🔍 Checking if swapDirection == .lightningToOnchain: \(self.swapDirection == .lightningToOnchain)")
                                
                                if self.swapDirection == .lightningToOnchain {
                                    print("🔄 Processing lightning to onchain swap")
                                    if let transaction = dictionary!["transaction"] as? [String: Any] {
                                        print("📄 Transaction data: \(transaction)")
                                        if let transactionHex = transaction["hex"] as? String {
                                            print("🔗 Transaction hex found, length: \(transactionHex.count)")
                                            self.handleTransactionMempool(transactionHex: transactionHex)
                                        } else {
                                            print("❌ No transaction hex found in response")
                                        }
                                    } else {
                                        print("❌ No transaction data found in response")
                                        
                                        // Fallback: Try to load lockup transaction from JSON file
                                        print("🔄 Attempting to load lockup transaction from JSON file...")
                                        if let swapID = self.coreVC?.bittrWallet.ongoingSwap?.boltzID,
                                           let jsonLockupTx = self.loadLockupTxFromFile(swapID: swapID) {
                                            print("✅ Found lockup transaction in JSON file, processing...")
                                            self.handleTransactionMempool(transactionHex: jsonLockupTx)
                                        } else {
                                            print("❌ No lockup transaction found in JSON file either")
                                        }
                                    }
                                } else {
                                    print("ℹ️ Not a lightning to onchain swap (direction: \(self.swapDirection))")
                                }
                            } else {
                                print("ℹ️ Other status received: \(receivedStatus)")
                            }
                        } else {
                            print("❌ No status received or invalid response format")
                            print("📄 Full response: \(dictionary ?? [:])")
                        }
                    }
                }
            } else {
                print("❌ No swap ID found in ongoing swap")
            }
        }
    }
    
    func userFriendlyStatus(receivedStatus:String) -> String {
        
        self.statusQuestionButton.accessibilityIdentifier = receivedStatus
        
        switch receivedStatus {
        case "swap.created": return Language.getWord(withID: "swapstatuspreparing")
        case "invoice.set": return Language.getWord(withID: "swapstatuspreparing")
        case "transaction.mempool": return Language.getWord(withID: "swapstatusawaitingconfirmation")
        case "transaction.confirmed": if self.swapDirection == .onchainToLightning {
            return Language.getWord(withID: "swapstatusawaitingpayment")
        } else {
            return Language.getWord(withID: "swapstatusswapcomplete")
        }
        case "invoice.pending": return Language.getWord(withID: "swapstatusinvoicepending")
        case "invoice.paid": return Language.getWord(withID: "swapstatusswapcomplete")
        case "invoice.failedToPay": return Language.getWord(withID: "swapstatusfailedtopay")
        case "transaction.claim.pending": return Language.getWord(withID: "swapstatusswapcomplete")
        case "transaction.claimed": return Language.getWord(withID: "swapstatusswapcomplete")
        case "swap.expired": return Language.getWord(withID: "swapstatusexpired")
        case "transaction.lockupFailed": return Language.getWord(withID: "swapstatusincorrectamount")
        case "invoice.settled": return Language.getWord(withID: "swapstatusswapcomplete")
        case "invoice.expired": return Language.getWord(withID: "swapstatusinvoicexpired")
        case "transaction.failed": return Language.getWord(withID: "swapstatusfailed")
        case "transaction.refunded": return Language.getWord(withID: "swapstatusfailed")
        default: return receivedStatus
        }
    }
    
    func confirmExpectedFees() {
        
        self.nextLabel.alpha = 1
        self.nextSpinner.stopAnimating()
        
        guard let ongoingSwap = self.coreVC?.bittrWallet.ongoingSwap else { return }
        
        let bitcoinValue = self.getCorrectBitcoinValue(coreVC: self.coreVC!)
        
        // Calculate total fees including claim transaction fee for lightning-to-onchain swaps
        // For lightning-to-onchain swaps, the claim transaction fee is included in the on-chain amount
        // so the user receives exactly what they input
        let totalFees = ongoingSwap.onchainFees! + ongoingSwap.lightningFees! + (ongoingSwap.claimTransactionFee ?? 0)
        
        var convertedFees = "\(CGFloat(Int(totalFees.inBTC()*bitcoinValue.currentValue*100))/100)".replacingOccurrences(of: ".", with: ",")
        if convertedFees.split(separator: ",")[1].count == 1 {
            convertedFees = convertedFees + "0"
        }
        let convertedAmount = "\(Int((ongoingSwap.satoshisAmount.inBTC()*bitcoinValue.currentValue).rounded()))"
        
        let message = Language.getWord(withID: "swapfunds3").replacingOccurrences(of: "<feesamount>", with: "\(totalFees)").replacingOccurrences(of: "<convertedfees>", with: "\(bitcoinValue.chosenCurrency) \(convertedFees)").replacingOccurrences(of: "<amount>", with: "\(self.coreVC!.bittrWallet.ongoingSwap!.satoshisAmount)".addSpaces()).replacingOccurrences(of: "<convertedamount>", with: "\(bitcoinValue.chosenCurrency) \(convertedAmount)")
        
        self.showAlert(
            presentingController: self,
            title: Language.getWord(withID: "swapfunds2"),
            message: message,
            buttons: [Language.getWord(withID: "cancel"), Language.getWord(withID: "proceed")],
            actions: [#selector(self.cancelSwapFromFeesAlert), #selector(self.proceedWithSwap)]
        )
    }
    
    @objc func cancelSwapFromFeesAlert() {
        self.hideAlert()
        // Clear all pending data and reset the UI
        self.clearPendingSwapData()
        // Reset the view to the initial state
        self.switchView("main")
    }
    
    @objc func proceedWithSwap() {
        self.hideAlert()
        
        guard let ongoingSwap = self.coreVC?.bittrWallet.ongoingSwap else { return }
        
        // Save ongoing swap to cache.
        CacheManager.saveLatestSwap(ongoingSwap)
        
        // Update the swap file with fees
        self.confirmDirectionLabel.text = self.fromLabel.text
        self.confirmAmountLabel.text = "\(ongoingSwap.satoshisAmount)".addSpaces() + " sats"
        let totalFees = (ongoingSwap.onchainFees ?? 0) + (ongoingSwap.lightningFees ?? 0) + (ongoingSwap.claimTransactionFee ?? 0)
        self.confirmFeesLabel.text = "\(totalFees)".addSpaces() + " sats"
        self.confirmStatusLabel.text = "Sending"
        self.confirmStatusSpinner.startAnimating()
        self.switchView("confirm")
        
        var direction = 0
        if self.swapDirection == .lightningToOnchain { direction = 1 }
        SwapManager.updateSwapFileWithFees(swapID: ongoingSwap.boltzID!, totalFees: totalFees, userAmount: ongoingSwap.satoshisAmount, direction: direction)
        
        if ongoingSwap.swapDirection == .onchainToLightning {
            SwapManager.sendOnchainPayment(swapVC: self)
        } else {
            SwapManager.sendLightningPayment(swapVC: self)
        }
    }
    
    // Clear pending addresses and invoices when swaps are cancelled or aborted
    func clearPendingSwapData() {
        self.coreVC!.bittrWallet.ongoingSwap = nil
        CacheManager.saveLatestSwap(nil)
        self.pendingOnchainAddress = ""
        self.pendingLightningInvoice = ""
        self.pendingOnchainAmount = 0
        self.isFromLightningPayment = false
        self.isFromOnchainPayment = false
        // Clear the amount field to make it obvious this is a fresh swap
        self.amountTextField.text = ""
    }
    
    func didCompleteOnchainTransaction() {
        
        // It may take significant time (e.g. 30 minutes) for the onchain transaction to be confirmed. We need to wait for this confirmation.
        
        self.confirmStatusLabel.text = Language.getWord(withID: "swapstatusawaitingconfirmation")
        CacheManager.saveLatestSwap(self.coreVC!.bittrWallet.ongoingSwap!)
        
        self.webSocketManager = WebSocketManager()
        self.webSocketManager!.delegate = self
        self.webSocketManager!.swapID = self.coreVC!.bittrWallet.ongoingSwap!.boltzID!
        self.webSocketManager!.connect()
    }
    
    func receivedStatusUpdate(status:String, fullMessage: [String: Any]) {
        
        guard let ongoingSwap = self.coreVC?.bittrWallet.ongoingSwap else { return }
        
        self.confirmStatusLabel.text = self.userFriendlyStatus(receivedStatus: status)
        
        if status == "invoice.failedToPay" || status == "transaction.lockupFailed" {
            self.confirmStatusSpinner.stopAnimating()
            // Boltz's payment has failed and we want to get a refund our onchain transaction. Get a partial signature through /swap/submarine/swapID/refund. Or a scriptpath refund can be done after the locktime of the swap expires.
            
            Task {
                do {
                    let result = try await BoltzRefund.tryBoltzRefund(swapVC: self)
                    print("Result: \(result)")
                } catch {
                    print("Error: \(error)")
                }
            }
        } else if status == "transaction.mempool", self.swapDirection == .lightningToOnchain {
            // Handle transaction.mempool for reverse swaps
            if let transaction = fullMessage["transaction"] as? [String: Any],
               let transactionHex = transaction["hex"] as? String {
                self.handleTransactionMempool(transactionHex: transactionHex)
            }
        } else if status == "transaction.claimed" {
            // Once the transaction.claimed status appears, it's the final status so we can stop spinning
            self.confirmStatusSpinner.stopAnimating()
            // We should also close the websocket connection and stop the background task
            self.webSocketManager?.disconnect()
        }
    }
    
    @IBAction func backgroundTapped(_ sender: UIButton) {
        self.view.endEditing(true)
    }
    
    @objc func askForPushNotifications() {
        
        self.hideAlert()
        
        let current = UNUserNotificationCenter.current()
        current.getNotificationSettings { (settings) in
            
            if settings.authorizationStatus == .notDetermined {
                // User hasn't set their preference yet.
                
                current.delegate = self
                current.requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
                    
                    print("Permission granted: \(granted)")
                    guard granted else {
                        return
                    }
                    
                    // Double check that the preference is now authorized.
                    current.getNotificationSettings { (settings) in
                        print("Notification settings: \(settings)")
                        guard settings.authorizationStatus == .authorized else {
                            return
                        }
                        DispatchQueue.main.async {
                            // Register for notifications.
                            UIApplication.shared.registerForRemoteNotifications()
                        }
                    }
                }
            } else if settings.authorizationStatus == .authorized {
                // User has already authorized notifications.
                DispatchQueue.main.async {
                    // Register for notifications.
                    UIApplication.shared.registerForRemoteNotifications()
                }
            }
        }
    }
    
    @objc func handleSwapNotification(notification: NSNotification) {
        if let userInfo = notification.userInfo as? [String: Any],
           let swapID = userInfo["swap_id"] as? String {
            
            print("Received swap notification for ID: \(swapID)")
            
            guard let ongoingSwap = self.coreVC?.bittrWallet.ongoingSwap else { return }
            
            // Set up the confirm view with loaded data
            self.swapDirection = ongoingSwap.swapDirection
            
            // Ensure view is loaded before accessing UI elements
            DispatchQueue.main.async {
                // Update UI labels
                self.confirmDirectionLabel?.text = ongoingSwap.dateID.contains("onchain to lightning") ?
                    Language.getWord(withID: "onchaintolightning") :
                    Language.getWord(withID: "lightningtoonchain")
                self.confirmAmountLabel?.text = "\(ongoingSwap.satoshisAmount)".addSpaces() + " sats"
                self.confirmFeesLabel?.text = "\((ongoingSwap.lightningFees ?? 0) + (ongoingSwap.onchainFees ?? 0))".addSpaces() + " sats"
                
                // Set status based on notification data
                if let status = userInfo["status"] as? String {
                    self.confirmStatusLabel?.text = self.userFriendlyStatus(receivedStatus: status)
                    
                    // Stop spinner if swap is complete or failed
                    if status == "transaction.claimed" || status == "invoice.settled" ||
                       status == "swap.expired" || status == "transaction.failed" {
                        self.confirmStatusSpinner?.stopAnimating()
                    }
                }
                
                // Switch to confirm view
                self.switchView("confirm")
                
                // Set up WebSocket if needed
                self.webSocketManager = WebSocketManager()
                self.webSocketManager!.delegate = self
                self.webSocketManager!.swapID = ongoingSwap.boltzID!
                self.webSocketManager!.connect()
            }
        }
    }
    
    private func checkForOngoingSwap() {
        // Check if there's an ongoing swap and automatically show it
        var pendingSwap = self.coreVC?.bittrWallet.ongoingSwap
        if pendingSwap == nil {
            pendingSwap = CacheManager.getLatestSwap()
        }
        if pendingSwap != nil {
            self.coreVC?.bittrWallet.ongoingSwap = pendingSwap
            
            // Set up the confirm view with loaded data
            self.swapDirection = pendingSwap!.swapDirection
            
            // Update UI labels
            self.confirmDirectionLabel?.text = pendingSwap!.dateID.contains("onchain to lightning") ?
                Language.getWord(withID: "onchaintolightning") :
                Language.getWord(withID: "lightningtoonchain")
            self.confirmAmountLabel?.text = "\(pendingSwap!.satoshisAmount)".addSpaces() + " sats"
            let totalFees = (pendingSwap!.onchainFees ?? 0) + (pendingSwap!.lightningFees ?? 0) + (pendingSwap!.claimTransactionFee ?? 0)
            self.confirmFeesLabel?.text = "\(totalFees)".addSpaces() + " sats"
            
            // Set initial status
            self.confirmStatusLabel?.text = Language.getWord(withID: "swapstatuspreparing")
            
            // Switch to confirm view
            self.switchView("confirm")
            
            // Set up WebSocket if needed
            self.webSocketManager = WebSocketManager()
            self.webSocketManager!.delegate = self
            self.webSocketManager!.swapID = pendingSwap!.boltzID!
            self.webSocketManager!.connect()
        }
    }
    
    private func handlePendingLightningInvoice() {
        // Parse the pending Lightning invoice to get the amount
        if let parsedInvoice = Bindings.Bolt11Invoice.fromStr(s: self.pendingLightningInvoice).getValue() {
            if let invoiceAmountMilli = parsedInvoice.amountMilliSatoshis() {
                let invoiceAmount = Int(invoiceAmountMilli)/1000
                
                // Set the amount and direction
                self.amountTextField.text = "\(invoiceAmount)"
                self.swapDirection = .onchainToLightning
                self.fromLabel.text = Language.getWord(withID: "onchaintolightning")
                
                // Create Swap object.
                self.coreVC!.bittrWallet.ongoingSwap = Swap()
                self.coreVC!.bittrWallet.ongoingSwap!.satoshisAmount = invoiceAmount
                self.coreVC!.bittrWallet.ongoingSwap!.swapDirection = .onchainToLightning
                
                // Start the swap process
                Task {
                    await SwapManager.onchainToLightning(amountMsat: UInt64(invoiceAmount*1000), swapVC: self, existingInvoice: self.pendingLightningInvoice)
                }
            } else {
                // Zero amount invoice - user needs to enter amount
                self.showAlert(presentingController: self, title: Language.getWord(withID: "enteramount"), message: Language.getWord(withID: "enteramountofsatoshis"), buttons: [Language.getWord(withID: "okay")], actions: nil)
            }
        } else {
            // Invalid invoice
            self.showAlert(presentingController: self, title: Language.getWord(withID: "error"), message: Language.getWord(withID: "invalidinvoice"), buttons: [Language.getWord(withID: "okay")], actions: nil)
        }
    }
    
    private func handlePendingOnchainPayment() {
        print("DEBUG - handlePendingOnchainPayment called. pendingOnchainAddress: \(self.pendingOnchainAddress), pendingOnchainAmount: \(self.pendingOnchainAmount)")
        // Set the amount and direction for Lightning to onchain swap
        self.amountTextField.text = "\(self.pendingOnchainAmount)"
        self.swapDirection = .lightningToOnchain
        self.fromLabel.text = Language.getWord(withID: "lightningtoonchain")
        
        // Create Swap object.
        self.coreVC!.bittrWallet.ongoingSwap = Swap()
        self.coreVC!.bittrWallet.ongoingSwap!.satoshisAmount = self.pendingOnchainAmount
        self.coreVC!.bittrWallet.ongoingSwap!.swapDirection = .lightningToOnchain
        
        // Start the swap process
        Task {
            await SwapManager.lightningToOnchain(amountSat: self.pendingOnchainAmount, swapVC: self, payoutAddress: self.pendingOnchainAddress)
        }
    }
    
    private func handleNotificationSwap() {
        print("DEBUG - handleNotificationSwap called. pendingOnchainAmount: \(self.pendingOnchainAmount)")
        // Set the amount and direction for lightning to onchain swap (to free up Lightning capacity)
        self.amountTextField.text = "\(self.pendingOnchainAmount)"
        self.swapDirection = .lightningToOnchain
        self.fromLabel.text = Language.getWord(withID: "lightningtoonchain")
        
        // Create Swap object.
        self.coreVC!.bittrWallet.ongoingSwap = Swap()
        self.coreVC!.bittrWallet.ongoingSwap!.satoshisAmount = self.pendingOnchainAmount
        self.coreVC!.bittrWallet.ongoingSwap!.swapDirection = .lightningToOnchain
        
        // Show spinner to indicate we're starting the swap process
        self.nextLabel.alpha = 0
        self.nextSpinner.startAnimating()
        
        // Start the swap process directly
        Task {
            await SwapManager.lightningToOnchain(amountSat: self.pendingOnchainAmount, swapVC: self, payoutAddress: nil)
        }
    }
    
    private func handleTransactionMempool(transactionHex: String) {
        print("🔧 handleTransactionMempool called with transaction hex length: \(transactionHex.count)")
        
        // Update the swap file with the lockup transaction
        guard let ongoingSwap = self.coreVC?.bittrWallet.ongoingSwap else { 
            print("❌ No ongoing swap found")
            return 
        }
        
        print("✅ Found ongoing swap with ID: \(ongoingSwap.boltzID ?? "nil")")
        
        ongoingSwap.lockupTx = transactionHex
        self.coreVC!.bittrWallet.ongoingSwap!.lockupTx = transactionHex
        CacheManager.saveLatestSwap(ongoingSwap)
        SwapManager.updateSwapFileWithLockupTx(swapID: ongoingSwap.boltzID!, lockupTx: ongoingSwap.lockupTx!)
        
        print("💾 Updated swap file with lockup transaction")
        
        // Claim onchain transaction using async function
        Task {
            do {
                print("🚀 Starting Boltz claim process...")
                let claimResult = try await BoltzRefund.tryBoltzClaimInternalTransactionGeneration(swapVC: self)
                print("✅ Claim result: \(claimResult)")
                
                // Handle the result on main thread
                DispatchQueue.main.async {
                    if claimResult.success {
                        self.confirmStatusLabel.text = Language.getWord(withID: "swapstatusswapcomplete")
                        self.confirmStatusSpinner.stopAnimating()
                        self.webSocketManager?.disconnect()
                        
                        // Add the onchain transaction to the UI
                        if let transactionId = claimResult.transactionId {
                            SwapManager.addOnchainTransactionToUI(transactionId: transactionId, swapVC: self)
                        }
                    } else {
                        self.confirmStatusLabel.text = Language.getWord(withID: "swapstatusfailed")
                    }
                }
            } catch {
                print("Error claiming transaction: \(error)")
                DispatchQueue.main.async {
                    self.confirmStatusLabel.text = Language.getWord(withID: "swapstatusfailed")
                }
            }
        }
    }
    
    @IBAction func downloadSwapFileTapped(_ sender: UIButton) {
        self.view.endEditing(true)
        
        guard let ongoingSwap = self.coreVC!.bittrWallet.ongoingSwap else { return }
        
        do {
            // Get the documents directory
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let fileURL = documentsPath.appendingPathComponent("\(ongoingSwap.boltzID!).json")
            
            // Read the JSON data from file
            let jsonData = try Data(contentsOf: fileURL)
            
            let temporaryFolder = FileManager.default.temporaryDirectory
            let fileName = "Swap \(ongoingSwap.boltzID!).json"
            let temporaryFileURL = temporaryFolder.appendingPathComponent(fileName)
            
            try jsonData.write(to: temporaryFileURL)
            let vc = UIActivityViewController(activityItems: [temporaryFileURL], applicationActivities: [])
            self.present(vc, animated: true, completion: nil)
        } catch {
            print("Error loading swap details from file: \(error)")
        }
    }
    
    @IBAction func statusQuestionTapped(_ sender: UIButton) {
        self.view.endEditing(true)
        
        if let swapStatus = sender.accessibilityIdentifier {
            
            var answer = ""
            
            switch swapStatus {
            case "swap.created":
                if self.swapDirection == .onchainToLightning {
                    answer = Language.getWord(withID: "swapquestionswapcreated0")
                } else {
                    answer = Language.getWord(withID: "swapquestionswapcreated1")
                }
            case "invoice.set":
                answer = Language.getWord(withID: "swapquestionswapcreated0")
            case "transaction.mempool":
                if self.swapDirection == .onchainToLightning {
                    answer = Language.getWord(withID: "swapquestiontransactionmempool0")
                } else {
                    answer = Language.getWord(withID: "swapquestioncomplete1")
                }
            case "transaction.confirmed":
                if self.swapDirection == .onchainToLightning {
                    answer = Language.getWord(withID: "swapquestiontransactionconfirmed0")
                } else {
                    answer = Language.getWord(withID: "swapquestioncomplete1")
                }
            case "invoice.pending":
                answer = Language.getWord(withID: "swapquestioninvoicepending0")
            case "invoice.paid":
                answer = Language.getWord(withID: "swapquestioncomplete0")
            case "invoice.failedToPay":
                answer = Language.getWord(withID: "swapquestioninvoicefailedtopay0")
            case "transaction.claim.pending":
                answer = Language.getWord(withID: "swapquestioncomplete0")
            case "transaction.claimed":
                answer = Language.getWord(withID: "swapquestioncomplete0")
            case "swap.expired":
                if self.swapDirection == .onchainToLightning {
                    answer = Language.getWord(withID: "swapquestionexpired0")
                } else {
                    answer = Language.getWord(withID: "swapquestionexpired1")
                }
            case "transaction.lockupFailed":
                if self.swapDirection == .onchainToLightning {
                    answer = Language.getWord(withID: "swapquestionexpired0")
                } else {
                    answer = Language.getWord(withID: "swapquestionexpired1")
                }
            case "invoice.settled":
                answer = Language.getWord(withID: "swapquestioncomplete1")
            case "invoice.expired":
                answer = Language.getWord(withID: "swapquestionexpired1")
            case "transaction.failed":
                answer = Language.getWord(withID: "swapquestionexpired1")
            case "transaction.refunded":
                answer = Language.getWord(withID: "swapquestionexpired1")
            default: answer = ""
            }
            
            self.coreVC!.launchQuestion(question: Language.getWord(withID: "swapquestion"), answer: answer, type: nil)
        } else {
            self.coreVC!.launchQuestion(question: Language.getWord(withID: "swapquestion"), answer: Language.getWord(withID: "swapquestiongeneric"), type: nil)
        }
    }
    

    // MARK: - Input Accessory View
    private func createInputAccessoryView() -> UIView {
        let containerView = UIView(frame: CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: 44))
        containerView.backgroundColor = Colors.getColor("whiteorblue3")
        
        let toolbar = UIToolbar(frame: containerView.bounds)
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        toolbar.backgroundColor = .clear
        
        let flexSpace = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        let doneButton = UIBarButtonItem(title: Language.getWord(withID: "done"), style: .done, target: self, action: #selector(backgroundTapped))
        
        toolbar.items = [flexSpace, doneButton]
        toolbar.tintColor = Colors.getColor("blackorwhite")
        
        containerView.addSubview(toolbar)
        
        NSLayoutConstraint.activate([
            toolbar.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            toolbar.topAnchor.constraint(equalTo: containerView.topAnchor),
            toolbar.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])
        
        return containerView
    }

    // MARK: - JSON File Helper
    
    private func loadLockupTxFromFile(swapID: String) -> String? {
        print("🔍 Loading lockup transaction from file: \(swapID).json")
        
        do {
            // Get the documents directory
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let fileURL = documentsPath.appendingPathComponent("\(swapID).json")
            
            // Check if file exists
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                print("❌ Swap file not found at: \(fileURL.path)")
                return nil
            }
            
            // Read the JSON data from file
            let jsonData = try Data(contentsOf: fileURL)
            
            // Convert JSON Data to NSDictionary
            guard let dictionary = try JSONSerialization.jsonObject(with: jsonData, options: []) as? NSDictionary else {
                print("❌ Failed to parse JSON from file")
                return nil
            }
            
            // Extract lockup transaction
            if let lockupTx = dictionary["lockupTx"] as? String {
                print("✅ Found lockup transaction in JSON file")
                return lockupTx
            } else {
                print("❌ No lockup transaction found in JSON file")
                return nil
            }
            
        } catch {
            print("❌ Error loading lockup transaction from file: \(error)")
            return nil
        }
    }
}

extension UIViewController {
    
    func getCorrectBitcoinValue(coreVC:CoreViewController) -> BitcoinValue {
        
        let bitcoinValue = BitcoinValue()
        bitcoinValue.currentValue = coreVC.bittrWallet.valueInEUR ?? 0.0
        if UserDefaults.standard.value(forKey: "currency") as? String == "CHF" {
            bitcoinValue.currentValue = coreVC.bittrWallet.valueInCHF ?? 0.0
            bitcoinValue.chosenCurrency = "CHF"
            bitcoinValue.apiUrl = "https://getbittr.com/api/price/btc/historical/chf"
        }
        
        return bitcoinValue
    }
}
