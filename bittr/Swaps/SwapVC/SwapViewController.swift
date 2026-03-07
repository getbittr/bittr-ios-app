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
import Sentry

class SwapViewController: UIViewController, UITextFieldDelegate, UNUserNotificationCenterDelegate {

    // General
    @IBOutlet weak var mainScrollView: UIScrollView!
    @IBOutlet weak var mainContentView: UIView!
    @IBOutlet weak var mainContentViewBottom: NSLayoutConstraint!
    @IBOutlet weak var contentBackground: UIButton!
    
    // Card contents
    @IBOutlet weak var centerCard: UIView!
    @IBOutlet weak var centerBackground: UIButton!
    @IBOutlet weak var subtitleLabel: UILabel!
    @IBOutlet weak var moveLabel: UILabel!
    @IBOutlet weak var amountTextField: UITextField!
    
    // From view
    @IBOutlet weak var fromView: UIView!
    @IBOutlet weak var fromLabel: UILabel!
    @IBOutlet weak var fromButton: UIButton!
    
    // Available view
    @IBOutlet weak var bdkSpinner: UIActivityIndicatorView!
    @IBOutlet weak var availableAmountLabel: UILabel!
    @IBOutlet weak var availableButton: UIButton!
    @IBOutlet weak var questionMark: UIImageView!
    
    // Next view
    @IBOutlet weak var nextView: UIView!
    @IBOutlet weak var nextLabel: UILabel!
    @IBOutlet weak var nextButton: UIButton!
    @IBOutlet weak var nextSpinner: UIActivityIndicatorView!
    @IBOutlet weak var arrowIcon: UIImageView!
    
    // Swap status
    @IBOutlet weak var statusContainer: UIView!
    @IBOutlet weak var scrollViewTrailing: NSLayoutConstraint!
    
    // VCs
    var coreVC:CoreViewController?
    var homeVC:HomeViewController?
    var swapStatusVC:SwapStatusViewController?
    
    // Swap details
    var swapDirection:SwapDirection = .lightningToOnchain
    var isFromLightningPayment = false
    var pendingLightningInvoice = ""
    var isFromOnchainPayment = false
    var pendingOnchainAddress = ""
    var pendingOnchainAmount = 0
    var highestFeePerVbyte:Float?
    var thisSwap:Swap?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Basics
        self.setBasicStyling()
        self.changeColors()
        self.setLanguage()
        self.addHeader(iconLight: "iconswapwhite", iconDark: "iconswap", title: Language.getWord(withID: "swapfunds"))
        
        // Available amount
        self.calculateSendableAmount()
    }
    
    func handlePendingSwaps() {
        
        // Check if there's an ongoing swap and automatically show it (only if from background notification)
        if self.isFromLightningPayment && !self.pendingLightningInvoice.isEmpty {
            Log.info("Handle pending Lightning invoice")
            self.handlePendingLightningInvoice()
            
        } else if self.isFromOnchainPayment && !self.pendingOnchainAddress.isEmpty {
            Log.info("Handle pending onchain payment")
            self.handlePendingOnchainPayment()
            
        } else if self.pendingOnchainAmount > 0 {
            Log.info("Handle swap suggested from pending Bittr payout.")
            self.handleNotificationSwap()
            
        }
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
            self.calculateSendableAmount()
        }
        let lightningToOnchain = UIAlertAction(title: Language.getWord(withID: "lightningtoonchain"), style: .default) { (action) in
            
            self.fromLabel.text = Language.getWord(withID: "lightningtoonchain")
            self.swapDirection = .lightningToOnchain
            self.calculateSendableAmount()
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
        
        // Check BDK availability.
        if self.swapDirection == .onchainToLightning && (BitcoinManager.shared.bdkWallet == nil || !BitcoinManager.shared.bdkWalletHasBeenScanned) {
            Log.info("BDK wallet isn't available yet.")
            self.bdkWalletUnavailable()
            return
        }
        
        // Check amount to be sent.
        let amountToBeSent = Int((self.amountTextField.text ?? "0").toNumber())
        guard amountToBeSent != 0 else {
            // No amount has been entered.
            self.showAlert(presentingController: self, title: Language.getWord(withID: "swapfunds2"), message: Language.getWord(withID: "enteramountofsatoshis"), buttons: [Language.getWord(withID: "okay")], actions: nil)
            return
        }
        
        // Get active channel.
        let activeChannel:LDKNode.ChannelDetails? = self.coreVC!.bittrWallet.lightningChannels.getActiveChannel()
        
        // Check budget availability.
        let maxAmount = (activeChannel?.inboundHtlcMaximumMsat ?? 0)/1000
        guard !(amountToBeSent > maxAmount) else {
            // You can't receive or send this much.
            self.showAlert(presentingController: self, title: Language.getWord(withID: "swapfunds2"), message: Language.getWord(withID: "swapamountexceeded").replacingOccurrences(of: "<amount>", with: "\(maxAmount)"), buttons: [Language.getWord(withID: "okay")], actions: nil)
            return
        }
        
        // Start loading.
        self.nextLabel.alpha = 0
        self.arrowIcon.alpha = 0
        self.nextSpinner.startAnimating()
        
        // Create Swap object.
        self.thisSwap = Swap()
        self.thisSwap!.satoshisAmount = amountToBeSent
        self.thisSwap!.swapDirection = self.swapDirection
        
        Task {
            if self.thisSwap!.swapDirection == .onchainToLightning {
                await SwapManager.onchainToLightning(amountMsat: UInt64(amountToBeSent*1000), swapVC: self)
            } else {
                await SwapManager.lightningToOnchain(amountSat: amountToBeSent, swapVC: self)
            }
        }
    }
    
    func showStatusView() {
        guard self.thisSwap != nil else { return }
        Log.info("Will show swap status view.")
        
        DispatchQueue.main.async {
            let storyboard = UIStoryboard(name: "Main", bundle: Bundle.main)
            let newChild = storyboard.instantiateViewController(withIdentifier: "SwapStatus")
            (newChild as? SwapStatusViewController)?.coreVC = self.coreVC
            (newChild as? SwapStatusViewController)?.swapVC = self
            (newChild as? SwapStatusViewController)?.thisSwap = self.thisSwap!
            self.swapStatusVC = (newChild as? SwapStatusViewController)
            
            self.addChild(newChild)
            newChild.view.frame.size = self.statusContainer.frame.size
            self.statusContainer.addSubview(newChild.view)
            newChild.didMove(toParent: self)
            
            UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseInOut) {
                NSLayoutConstraint.deactivate([self.scrollViewTrailing])
                self.scrollViewTrailing = NSLayoutConstraint(item: self.mainScrollView, attribute: .trailing, relatedBy: .equal, toItem: self.view, attribute: .leading, multiplier: 1, constant: 0)
                NSLayoutConstraint.activate([self.scrollViewTrailing])
                self.view.layoutIfNeeded()
            }
        }
    }
    
    func hideStatusView() {
        Log.info("Will hide swap status view.")
        
        UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseInOut) {
            NSLayoutConstraint.deactivate([self.scrollViewTrailing])
            self.scrollViewTrailing = NSLayoutConstraint(item: self.mainScrollView, attribute: .trailing, relatedBy: .equal, toItem: self.view, attribute: .trailing, multiplier: 1, constant: 0)
            NSLayoutConstraint.activate([self.scrollViewTrailing])
            self.view.layoutIfNeeded()
        } completion: { _ in
            for eachSubview in self.statusContainer.subviews {
                eachSubview.removeFromSuperview()
            }
            self.swapStatusVC = nil
        }
    }
    
    func confirmExpectedFees() {
        
        self.nextLabel.alpha = 1
        self.arrowIcon.alpha = 1
        self.nextSpinner.stopAnimating()
        
        guard self.thisSwap != nil else { return }
        
        let bitcoinValue = self.getCorrectBitcoinValue(coreVC: self.coreVC!)
        
        // Calculate total fees including claim transaction fee for lightning-to-onchain swaps
        // For lightning-to-onchain swaps, the claim transaction fee is included in the on-chain amount
        // so the user receives exactly what they input
        let totalFees = self.thisSwap!.onchainFees! + self.thisSwap!.lightningFees! + (self.thisSwap!.claimTransactionFee ?? 0)
        
        var convertedFees = "\(CGFloat(Int(totalFees.inBTC()*bitcoinValue.currentValue*100))/100)".replacingOccurrences(of: ".", with: ",")
        if convertedFees.split(separator: ",")[1].count == 1 {
            convertedFees = convertedFees + "0"
        }
        let convertedAmount = "\(Int((self.thisSwap!.satoshisAmount.inBTC()*bitcoinValue.currentValue).rounded()))"
        
        let message = Language.getWord(withID: "swapfunds3").replacingOccurrences(of: "<feesamount>", with: "\(totalFees)").replacingOccurrences(of: "<convertedfees>", with: "\(bitcoinValue.chosenCurrency) \(convertedFees)").replacingOccurrences(of: "<amount>", with: "\(self.thisSwap!.satoshisAmount)".addSpaces()).replacingOccurrences(of: "<convertedamount>", with: "\(bitcoinValue.chosenCurrency) \(convertedAmount)")
        
        self.showAlert(
            presentingController: self,
            title: Language.getWord(withID: "swapfunds2"),
            message: message,
            buttons: [Language.getWord(withID: "cancel"), Language.getWord(withID: "proceed")],
            actions: [#selector(self.cancelSwapFromFeesAlert), #selector(self.proceedWithSwap)]
        )
    }
    
    @objc func cancelSwapFromFeesAlert() {
        Log.info("Cancel swap from fees alert.")
        self.hideAlert()
        // Clear all pending data and reset the UI
        self.clearPendingSwapData()
    }
    
    @objc func proceedWithSwap() {
        Log.info("Proceed with swap.")
        self.hideAlert()
        guard self.thisSwap != nil else { return }
        
        // Save ongoing swap to cache.
        CacheManager.saveLatestSwap(self.thisSwap!)
        
        // Show swap status.
        self.showStatusView()
        
        // Update swap file.
        let direction = (self.thisSwap!.swapDirection == .lightningToOnchain) ? 1 : 0
        SwapManager.updateSwapFileWithFees(swapID: self.thisSwap!.boltzID!, totalFees: (self.thisSwap!.onchainFees ?? 0) + (self.thisSwap!.lightningFees ?? 0) + (self.thisSwap!.claimTransactionFee ?? 0), userAmount: self.thisSwap!.satoshisAmount, direction: direction)
        
        // Send payment.
        if self.thisSwap!.swapDirection == .onchainToLightning {
            SwapManager.sendOnchainPayment(swapVC: self)
        } else {
            self.performLightningPayment()
        }
    }
    
    func clearPendingSwapData() {
        // Clear pending addresses and invoices when swaps are cancelled or aborted.
        self.pendingOnchainAddress = ""
        self.pendingLightningInvoice = ""
        self.pendingOnchainAmount = 0
        self.isFromLightningPayment = false
        self.isFromOnchainPayment = false
        self.amountTextField.text = ""
    }
    
    @IBAction func backgroundTapped(_ sender: UIButton) {
        self.view.endEditing(true)
    }
    
    func handleSwapNotification(_ notification: BittrNotification) {
        Log.info("Received swap notification.")
        guard notification.swapID != nil, let ongoingSwap = SwapManager.loadSwapDetailsFromFile(swapID: notification.swapID!)?.toSwap() else { return }
        
        // Set up the confirm view with loaded data
        self.thisSwap = ongoingSwap
        
        // Switch to confirm view
        self.showStatusView()
    }
    
    func handlePendingLightningInvoice() {
        // Parse the pending Lightning invoice to get the amount
        if let parsedInvoice = Bindings.Bolt11Invoice.fromStr(s: self.pendingLightningInvoice).getValue() {
            if let invoiceAmountMilli = parsedInvoice.amountMilliSatoshis() {
                let invoiceAmount = Int(invoiceAmountMilli)/1000
                
                // Set the amount and direction
                self.amountTextField.text = "\(invoiceAmount)"
                self.swapDirection = .onchainToLightning
                self.fromLabel.text = Language.getWord(withID: "onchaintolightning")
                
                // Start loading.
                self.nextLabel.alpha = 0
                self.arrowIcon.alpha = 0
                self.nextSpinner.startAnimating()
                
                // Create Swap object.
                self.thisSwap = Swap()
                self.thisSwap!.satoshisAmount = invoiceAmount
                self.thisSwap!.swapDirection = .onchainToLightning
                
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
    
    func handlePendingOnchainPayment() {
        Log.info("handlePendingOnchainPayment called.")
        // Set the amount and direction for Lightning to onchain swap
        self.amountTextField.text = "\(self.pendingOnchainAmount)"
        self.swapDirection = .lightningToOnchain
        self.fromLabel.text = Language.getWord(withID: "lightningtoonchain")
        
        // Start loading.
        self.nextLabel.alpha = 0
        self.arrowIcon.alpha = 0
        self.nextSpinner.startAnimating()
        
        // Create Swap object.
        self.thisSwap = Swap()
        self.thisSwap!.satoshisAmount = self.pendingOnchainAmount
        self.thisSwap!.swapDirection = .lightningToOnchain
        
        // Start the swap process
        Task {
            await SwapManager.lightningToOnchain(amountSat: self.pendingOnchainAmount, swapVC: self, payoutAddress: self.pendingOnchainAddress)
        }
    }
    
    func handleNotificationSwap() {
        Log.info("handleNotificationSwap called.")
        // Set the amount and direction for lightning to onchain swap (to free up Lightning capacity)
        self.amountTextField.text = "\(self.pendingOnchainAmount)"
        self.swapDirection = .lightningToOnchain
        self.fromLabel.text = Language.getWord(withID: "lightningtoonchain")
        
        // Create Swap object.
        self.thisSwap = Swap()
        self.thisSwap!.satoshisAmount = self.pendingOnchainAmount
        self.thisSwap!.swapDirection = .lightningToOnchain
        
        // Show spinner to indicate we're starting the swap process
        self.nextLabel.alpha = 0
        self.arrowIcon.alpha = 0
        self.nextSpinner.startAnimating()
        
        // Start the swap process directly
        Task {
            await SwapManager.lightningToOnchain(amountSat: self.pendingOnchainAmount, swapVC: self, payoutAddress: nil)
        }
    }
    

    // MARK: - Input Accessory View
    func createInputAccessoryView() -> UIView {
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
}
