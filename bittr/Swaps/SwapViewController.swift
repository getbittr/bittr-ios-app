//
//  SwapViewController.swift
//  bittr
//
//  Created by Tom Melters on 24/01/2025.
//

import UIKit
import LDKNode

class SwapViewController: UIViewController, UITextFieldDelegate {

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
    
    // Pending stack
    @IBOutlet weak var pendingStack: UIView!
    @IBOutlet weak var pendingStackHeight: NSLayoutConstraint! // 0 or 75
    @IBOutlet weak var pendingView: UIView!
    @IBOutlet weak var pendingButton: UIButton!
    @IBOutlet weak var pendingCoverView: UIView!
    @IBOutlet weak var pendingSpinner: UIActivityIndicatorView!
    
    // Variables
    var homeVC:HomeViewController?
    var swapDirection = 0
    var amountToBeSent:Int?
    var pendingInvoice:Bolt11Invoice?
    var swapDictionary:NSDictionary?
    var webSocketManager:WebSocketManager?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Button titles
        self.downButton.setTitle("", for: .normal)
        self.centerBackground.setTitle("", for: .normal)
        self.contentBackground.setTitle("", for: .normal)
        self.nextButton.setTitle("", for: .normal)
        self.availableButton.setTitle("", for: .normal)
        self.fromButton.setTitle("", for: .normal)
        self.confirmStatusButton.setTitle("", for: .normal)
        self.pendingButton.setTitle("", for: .normal)
        
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
        if let actualChannel = self.homeVC?.coreVC?.bittrChannel {
            self.availableAmountLabel.text = Language.getWord(withID: "satsatatime").replacingOccurrences(of: "<amount>", with: "\(actualChannel.receivableMaximum)")
        }

        // Set colors and language
        self.changeColors()
        self.setLanguage()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillDisappear), name: UIResponder.keyboardWillHideNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillAppear), name: UIResponder.keyboardWillShowNotification, object: nil)
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
            self.swapDirection = 0
        }
        let lightningToOnchain = UIAlertAction(title: Language.getWord(withID: "lightningtoonchain"), style: .default) { (action) in
            
            self.fromLabel.text = Language.getWord(withID: "lightningtoonchain")
            self.swapDirection = 1
        }
        let cancelAction = UIAlertAction(title: Language.getWord(withID: "cancel"), style: .cancel, handler: nil)
        actionSheet.addAction(onchainToLightning)
        actionSheet.addAction(lightningToOnchain)
        actionSheet.addAction(cancelAction)
        present(actionSheet, animated: true, completion: nil)
    }
    
    @IBAction func availableAmountTapped(_ sender: UIButton) {
        self.view.endEditing(true)
        
        let notificationDict:[String: Any] = ["question":Language.getWord(withID: "limitlightning"),"answer":Language.getWord(withID: "limitlightninganswer"),"type":"lightningsendable"]
        NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "question"), object: nil, userInfo: notificationDict) as Notification)
    }
    
    @IBAction func nextTapped(_ sender: UIButton) {
        self.view.endEditing(true)
        
        // TODO: Hide after testing
        /*self.swapDictionary = ["bip21":"bitcoin:bcrt1p2tkzczfw4y5xqlxngqgt7rx4lv4wwva0k968u0nue2zw03th6zlsvte5zd?amount=0.00055357&label=Send%20to%20BTC%20lightning","acceptZeroConf":false,"expectedAmount":55357,"id":"zRX14hgFtYLY","address":"bcrt1p2tkzczfw4y5xqlxngqgt7rx4lv4wwva0k968u0nue2zw03th6zlsvte5zd","swapTree":["claimLeaf":["version":192,"output":"a914df3d48b0e6848a21773b9f08ba0e5fee449853cc882036ab60cdac08b58c176298582076c56a19388f209ca54c5aa6307ef14cdefc93ac"],"refundLeaf":["version":192,"output":"20da4bdf00584f344ffcaf99f954b5d0ead6124a7269ec404f0ee8ceb12866c315ad021d02b1"]],"claimPublicKey":"0336ab60cdac08b58c176298582076c56a19388f209ca54c5aa6307ef14cdefc93","timeoutBlockHeight":541]
        self.confirmDirectionLabel.text = self.fromLabel.text
        self.confirmAmountLabel.text = "55000 sats"
        self.confirmFeesLabel.text = "510 sats"
        self.confirmStatusLabel.text = "Sending"
        self.confirmStatusSpinner.startAnimating()
        self.switchView("confirm")
        self.didCompleteOnchainTransaction(swapDictionary:self.swapDictionary!)*/
        
        if self.nextSpinner.isAnimating { return }
        
        self.nextLabel.alpha = 0
        self.nextSpinner.startAnimating()
         
         if self.stringToNumber(self.amountTextField.text) != 0 {
            if Int(self.stringToNumber(self.amountTextField.text)) > 1000000 {
                // You can't receive or send this much.
                self.showAlert(presentingController: self, title: Language.getWord(withID: "swapfunds2"), message: Language.getWord(withID: "swapamountexceeded").replacingOccurrences(of: "<amount>", with: "\(self.homeVC!.coreVC!.bittrChannel!.receivableMaximum)"), buttons: [Language.getWord(withID: "okay")], actions: nil)
            } else {
                self.amountToBeSent = Int(self.stringToNumber(self.amountTextField.text))
                if self.swapDirection == 0 {
                    // Onchain to Lightning.
                    Task {
                        await SwapManager.onchainToLightning(amountMsat: UInt64(Int(self.stringToNumber(self.amountTextField.text))*1000), delegate: self)
                    }
                } else {
                    // Lightning to Onchain
                    Task {
                        await SwapManager.lightningToOnchain(amountSat: Int(self.stringToNumber(self.amountTextField.text)), delegate: self)
                    }
                }
            }
        }
    }
    
    @IBAction func pendingSwapTapped(_ sender: UIButton) {
        var pendingSwap = self.homeVC?.coreVC?.ongoingSwapDictionary
        if pendingSwap == nil {
            pendingSwap = CacheManager.getLatestSwap()
        }
        if pendingSwap != nil {
            self.homeVC?.coreVC?.ongoingSwapDictionary = pendingSwap
            self.switchView("confirm")
        }
    }
    
    func switchView(_ toView: String) {
        
        if toView == "confirm" {
            UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseInOut) {
                self.centerCardLeading.constant = 15 - self.view.bounds.width
                self.view.layoutIfNeeded()
            }
        } else {
            UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseInOut) {
                self.centerCardLeading.constant = 15
                self.view.layoutIfNeeded()
            }
        }
    }
    
    @IBAction func confirmStatusButtonTapped(_ sender: UIButton) {
        
        DispatchQueue.main.async {
            self.confirmStatusLabel.alpha = 0
            self.resetIcon.alpha = 0
            
            if let swapID = self.swapDictionary!["id"] as? String {
                SwapManager.checkSwapStatus(swapID) { status in
                    DispatchQueue.main.async {
                        self.confirmStatusLabel.alpha = 1
                        self.resetIcon.alpha = 1
                        if let receivedStatus = status {
                            
                            self.confirmStatusLabel.text = self.userFriendlyStatus(receivedStatus: receivedStatus)
                            
                            if receivedStatus == "invoice.failedToPay" || receivedStatus == "swap.expired" || receivedStatus == "transaction.lockupFailed" {
                                SwapManager.claimRefund()
                            }
                        } else {
                            print("No status received.")
                        }
                    }
                }
            }
        }
    }
    
    func userFriendlyStatus(receivedStatus:String) -> String {
        
        switch receivedStatus {
        case "swap.created": return Language.getWord(withID: "swapstatuspreparing")
        case "invoice.set": return Language.getWord(withID: "swapstatuspreparing")
        case "transaction.mempool": return Language.getWord(withID: "swapstatusawaitingconfirmation")
        case "transaction.confirmed": if self.swapDirection == 0 {
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
    
    func confirmExpectedFees(feeHigh:Float, onchainFees:Int, lightningFees:Int, swapDictionary:NSDictionary, createdInvoice:Bolt11Invoice) {
        
        self.nextLabel.alpha = 1
        self.nextSpinner.stopAnimating()
        
        self.pendingInvoice = createdInvoice
        
        var currency = "€"
        var correctAmount = self.homeVC!.coreVC!.eurValue
        if UserDefaults.standard.value(forKey: "currency") as? String == "CHF" {
            correctAmount = self.homeVC!.coreVC!.chfValue
            currency = "CHF"
        }
        var convertedFees = "\(CGFloat(Int(CGFloat(onchainFees + lightningFees)/100000000*correctAmount*100))/100)".replacingOccurrences(of: ".", with: ",")
        if convertedFees.split(separator: ",")[1].count == 1 {
            convertedFees = convertedFees + "0"
        }
        let convertedAmount = "\(Int((CGFloat(self.amountToBeSent ?? 0)/100000000*correctAmount).rounded()))"
        
        let alert = UIAlertController(title: Language.getWord(withID: "swapfunds2"), message: Language.getWord(withID: "swapfunds3").replacingOccurrences(of: "<feesamount>", with: "\(onchainFees + lightningFees)").replacingOccurrences(of: "<convertedfees>", with: "\(currency) \(convertedFees)").replacingOccurrences(of: "<amount>", with: "\(self.amountToBeSent ?? 0)").replacingOccurrences(of: "<convertedamount>", with: "\(currency) \(convertedAmount)"), preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: Language.getWord(withID: "cancel"), style: .cancel, handler: nil))
        alert.addAction(UIAlertAction(title: Language.getWord(withID: "proceed"), style: .default, handler: { _ in
            
            let updatedDictionary:NSMutableDictionary = swapDictionary.mutableCopy() as! NSMutableDictionary
            updatedDictionary.setValue(onchainFees + lightningFees, forKey: "totalfees")
            updatedDictionary.setValue(self.amountToBeSent ?? 0, forKey: "useramount")
            updatedDictionary.setValue(self.swapDirection, forKey: "direction")
            self.swapDictionary = updatedDictionary
            self.homeVC?.coreVC?.ongoingSwapDictionary = updatedDictionary
            CacheManager.saveLatestSwap(updatedDictionary)
            self.confirmDirectionLabel.text = self.fromLabel.text
            self.confirmAmountLabel.text = "\(self.amountToBeSent ?? 0) sats"
            self.confirmFeesLabel.text = "\(onchainFees + lightningFees) sats"
            self.confirmStatusLabel.text = "Sending"
            self.confirmStatusSpinner.startAnimating()
            self.switchView("confirm")
            
            if self.swapDirection == 0 {
                SwapManager.sendOnchainPayment(feeHigh: feeHigh, onchainFees: onchainFees, lightningFees: lightningFees, receivedDictionary: self.swapDictionary!, delegate: self)
            } else {
                SwapManager.sendLightningPayment(swapDictionary: self.swapDictionary!, delegate: self)
            }
        }))
        self.present(alert, animated: true)
    }
    
    func didCompleteOnchainTransaction(swapDictionary:NSDictionary) {
        
        // It may take significant time (e.g. 30 minutes) for the onchain transaction to be confirmed. We need to wait for this confirmation.
        
        self.confirmStatusLabel.text = Language.getWord(withID: "swapstatusawaitingconfirmation")
        self.swapDictionary = swapDictionary
        self.homeVC?.coreVC?.ongoingSwapDictionary = swapDictionary
        CacheManager.saveLatestSwap(swapDictionary)
        
        if let swapID = swapDictionary["id"] as? String {
            self.webSocketManager = WebSocketManager()
            self.webSocketManager!.delegate = self
            self.webSocketManager!.swapID = swapID
            self.webSocketManager!.connect()
        }
    }
    
    func receivedStatusUpdate(status:String, fullMessage: [String: Any]) {
        
        self.confirmStatusLabel.text = self.userFriendlyStatus(receivedStatus: status)
        
        if status == "transaction.claim.pending" {
            
            // When status is transaction.claim.pending, get preimage details from API /swap/submarine/swapID/claim to verify that the Lightning payment has been made.
            
            if let swapID = self.swapDictionary?["id"] as? String {
                SwapManager.checkPreimageDetails(swapID: swapID, delegate: self)
            }
            
        } else if status == "invoice.failedToPay" || status == "transaction.lockupFailed" {
            
            // Boltz's payment has failed and we want to get a refund our onchain transaction. Get a partial signature through /swap/submarine/swapID/refund. Or a scriptpath refund can be done after the locktime of the swap expires.
            
            SwapManager.claimRefund()
        } else if status == "transaction.mempool", self.swapDirection == 1 {
            // Handle transaction.mempool for reverse swaps
            if let swapID = self.swapDictionary?["id"] as? String,
               let transaction = fullMessage["transaction"] as? [String: Any],
               let transactionHex = transaction["hex"] as? String {
                handleTransactionMempool(swapID: swapID, transactionHex: transactionHex)
            }
        } else if status == "transaction.claimed" {
            // Once the transaction.claimed status appears, it's the final status so we can stop spinning
            self.confirmStatusSpinner.stopAnimating()
            // We should also close the websocket connection and stop the background task
            self.webSocketManager!.disconnect()
        }
    }
    
    @IBAction func backgroundTapped(_ sender: UIButton) {
        self.view.endEditing(true)
    }
    
    private func handleTransactionMempool(swapID: String, transactionHex: String) {
        // Update the swap file with the lockup transaction
        SwapManager.updateSwapFileWithLockupTx(swapID: swapID, lockupTx: transactionHex)
        
        // Claim onchain transaction using async function
        Task {
            do {
                let claimResult = try await BoltzRefund.tryBoltzClaimInternalTransactionGeneration(swapId: swapID)
                print("Claim result: \(claimResult)")
                
                // Handle the result on main thread
                DispatchQueue.main.async {
                    if claimResult {
                        self.confirmStatusLabel.text = Language.getWord(withID: "swapstatusswapcomplete")
                        self.confirmStatusSpinner.stopAnimating()
                        self.webSocketManager?.disconnect()
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
    
    func setLanguage() {
        self.topLabel.text = Language.getWord(withID: "swapfunds")
        self.subtitleLabel.text = Language.getWord(withID: "swapsubtitle")
        self.moveLabel.text = Language.getWord(withID: "move")
        self.nextLabel.text = Language.getWord(withID: "next")
        self.fromLabel.text = Language.getWord(withID: "onchaintolightning")
        self.titleDirection.text = Language.getWord(withID: "direction")
        self.titleAmount.text = Language.getWord(withID: "amount")
        self.titleFees.text = Language.getWord(withID: "fees")
        self.titleStatus.text = Language.getWord(withID: "status")
    }
    
    func changeColors() {
        self.view.backgroundColor = Colors.getColor("yelloworblue1")
        self.topLabel.textColor = Colors.getColor("whiteoryellow")
        self.subtitleLabel.textColor = Colors.getColor("blackorwhite")
        self.moveLabel.textColor = Colors.getColor("blackoryellow")
        self.centerCard.backgroundColor = Colors.getColor("yelloworblue1")
        self.confirmCard.backgroundColor = Colors.getColor("yelloworblue1")
        self.pendingCoverView.backgroundColor = Colors.getColor("yelloworblue1")
        self.confirmTopLabel.textColor = Colors.getColor("whiteoryellow")
        self.confirmDirection.backgroundColor = Colors.getColor("whiteorblue3")
        self.confirmAmount.backgroundColor = Colors.getColor("whiteorblue3")
        self.confirmFees.backgroundColor = Colors.getColor("whiteorblue3")
        self.confirmStatus.backgroundColor = Colors.getColor("whiteorblue3")
        self.confirmDirectionLabel.textColor = Colors.getColor("blackorwhite")
        self.confirmAmountLabel.textColor = Colors.getColor("blackorwhite")
        self.confirmFeesLabel.textColor = Colors.getColor("blackorwhite")
        self.confirmStatusLabel.textColor = Colors.getColor("blackorwhite")
        self.availableAmountLabel.textColor = Colors.getColor("blackorwhite")
        self.questionMark.tintColor = Colors.getColor("blackorwhite")
        self.amountTextField.backgroundColor = Colors.getColor("white0.7orblue2")
        self.fromView.backgroundColor = Colors.getColor("whiteorblue3")
        self.fromLabel.textColor = Colors.getColor("blackorwhite")
        
        self.amountTextField.attributedPlaceholder = NSAttributedString(
            string: Language.getWord(withID: "enteramountofsatoshis"),
            attributes: [NSAttributedString.Key.foregroundColor: Colors.getColor("grey2orwhite0.7")]
        )
        
        if CacheManager.darkModeIsOn() {
            self.swapIcon.image = UIImage(named: "iconswap")
            self.confirmTopIcon.image = UIImage(named: "iconswap")
            self.resetIcon.image = UIImage(named: "iconresetwhite")
        } else {
            self.swapIcon.image = UIImage(named: "iconswapwhite")
            self.confirmTopIcon.image = UIImage(named: "iconswapwhite")
            self.resetIcon.image = UIImage(named: "iconreset")
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

}
