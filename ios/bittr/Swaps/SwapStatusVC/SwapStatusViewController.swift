//
//  SwapStatusViewController.swift
//  bittr
//
//  Created by Tom Melters on 3/6/26.
//

import UIKit
import Sentry

class SwapStatusViewController: UIViewController {
    
    // Card
    @IBOutlet weak var confirmCard: UIView!
    @IBOutlet weak var confirmTopLabel: UILabel!
    @IBOutlet weak var confirmTopIcon: UIImageView!
    
    // Direction
    @IBOutlet weak var confirmDirection: UIView!
    @IBOutlet weak var titleDirection: UILabel!
    @IBOutlet weak var confirmDirectionLabel: UILabel!
    
    // Amount
    @IBOutlet weak var confirmAmount: UIView!
    @IBOutlet weak var titleAmount: UILabel!
    @IBOutlet weak var confirmAmountLabel: UILabel!
    
    // Fees
    @IBOutlet weak var confirmFees: UIView!
    @IBOutlet weak var titleFees: UILabel!
    @IBOutlet weak var confirmFeesLabel: UILabel!
    
    // Status
    @IBOutlet weak var confirmStatus: UIView!
    @IBOutlet weak var titleStatus: UILabel!
    @IBOutlet weak var confirmStatusLabel: UILabel!
    @IBOutlet weak var resetIcon: UIImageView!
    @IBOutlet weak var confirmStatusSpinner: UIActivityIndicatorView!
    @IBOutlet weak var confirmStatusButton: UIButton!
    @IBOutlet weak var statusQuestionIcon: UIImageView!
    @IBOutlet weak var statusQuestionButton: UIButton!
    
    // Download swap details
    @IBOutlet weak var downloadView: UIView!
    @IBOutlet weak var downloadButton: UIButton!
    @IBOutlet weak var downloadIcon: UIImageView!
    @IBOutlet weak var downloadLabel: UILabel!
    
    // Variables
    var thisSwap:Swap?
    var coreVC:CoreViewController?
    var swapVC:SwapViewController?
    var webSocketManager:WebSocketManager?
    
    override func viewDidLoad() {
        super.viewDidLoad()

        self.confirmCard.accessibilityIdentifier = TestID.SwapStatus.confirmCard
        self.confirmStatusLabel.accessibilityIdentifier = TestID.SwapStatus.confirmStatusLabel
        self.confirmStatusButton.accessibilityIdentifier = TestID.SwapStatus.refreshButton

        // Button titles
        self.confirmStatusButton.setTitle("", for: .normal)
        self.downloadButton.setTitle("", for: .normal)
        self.statusQuestionButton.setTitle("", for: .normal)
        
        // Corner radii
        self.confirmCard.layer.cornerRadius = 13
        self.confirmDirection.layer.cornerRadius = 8
        self.confirmAmount.layer.cornerRadius = 8
        self.confirmFees.layer.cornerRadius = 8
        self.confirmStatus.layer.cornerRadius = 8
        self.downloadView.layer.cornerRadius = 8
        
        // Shadows
        self.confirmCard.setShadow()
        
        // Set colors and language
        self.changeColors()
        self.setLanguage()
        self.setSwap()
        
        // Header
        if self.swapVC == nil {
            self.addHeader(iconLight: "iconswapwhite", iconDark: "iconswap", title: Language.getWord(withID: "swapfunds"))
        }
    }
    
    func setSwap() {
        guard self.thisSwap != nil else { return }
        
        if self.swapVC == nil, let swapDictionary = SwapManager.loadSwapDetailsFromFile(swapID: self.thisSwap!.boltzID!) {
            // Load swap from TransactionVC.
            let fileSwap = swapDictionary.toSwap()
            fileSwap.onchainFees = self.thisSwap!.onchainFees
            fileSwap.lightningFees = self.thisSwap!.lightningFees
            if (self.thisSwap!.onchainFees ?? 0) > fileSwap.satoshisAmount {
                fileSwap.onchainFees = (self.thisSwap!.onchainFees ?? 0) - fileSwap.satoshisAmount
            }
            self.thisSwap = fileSwap
        }
        
        // Direction
        self.confirmDirectionLabel.text = self.thisSwap!.swapDirection == .lightningToOnchain ? Language.getWord(withID: "lightningtoonchain") : Language.getWord(withID: "onchaintolightning")
        
        // Amount
        self.confirmAmountLabel.text = "\(self.thisSwap!.satoshisAmount)".addSpaces() + " sats"
        
        // Fees
        let totalFees = (self.thisSwap!.onchainFees ?? 0) + (self.thisSwap!.lightningFees ?? 0) + (self.thisSwap!.claimTransactionFee ?? 0)
        self.confirmFeesLabel.text = "\(totalFees)".addSpaces() + " sats"
        
        // Status
        self.confirmStatusSpinner.startAnimating()
        self.confirmStatusLabel.text = "Checking"
        
        // Get status
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            SwapManager.checkSwapStatus(self.thisSwap!.boltzID!) { dictionary in
                DispatchQueue.main.async {
                    self.confirmStatusLabel.alpha = 1
                    self.confirmStatusSpinner.stopAnimating()
                    if dictionary != nil, let receivedStatus = dictionary!["status"] as? String {
                        self.receivedStatusUpdate(status: receivedStatus, fullMessage: dictionary! as! [String : Any])
                    } else {
                        Log.info("No status received.")
                    }
                }
            }
        }
    }
    
    // Keep the suggested-swap marker in sync with Boltz's status so Home and
    // the TransactionVC only show the payment as succeeded once the recipient
    // has actually been paid. (The lightning→onchain success case is handled
    // at claim broadcast in SwapManager.addOnchainTransactionToUI instead —
    // there the recipient is paid by our own claim transaction.)
    func syncSuggestedSwapMarker(status:String) {
        guard let ongoingSwap = self.thisSwap, ongoingSwap.isSuggested, ongoingSwap.dateID != "" else { return }

        switch status {
        case "invoice.paid", "transaction.claim.pending", "transaction.claimed", "invoice.settled":
            CacheManager.storeSuggestedSwap(dateID: ongoingSwap.dateID, status: .succeeded)
        case "invoice.failedToPay", "transaction.lockupFailed", "swap.expired", "invoice.expired", "transaction.failed", "transaction.refunded":
            CacheManager.storeSuggestedSwap(dateID: ongoingSwap.dateID, status: .failed)
        default:
            break
        }
    }

    func receivedStatusUpdate(status:String, fullMessage: [String: Any]) {
        guard self.thisSwap != nil else { return }

        self.syncSuggestedSwapMarker(status: status)
        self.statusQuestionButton.boundString = status
        self.confirmStatusLabel.text = status.userFriendlyStatus(direction: self.thisSwap!.swapDirection)
        
        if status == "invoice.failedToPay" || status == "transaction.lockupFailed" {
            self.confirmStatusSpinner.stopAnimating()
            // Boltz's payment has failed and we want to get a refund our onchain transaction. Get a partial signature through /swap/submarine/swapID/refund. Or a scriptpath refund can be done after the locktime of the swap expires.
            
            Task {
                do {
                    let result = try await BoltzRefund.tryBoltzRefund(swapVC: self)
                    print("Result: \(result)")
                } catch {
                    Log.info("Error: \(error)")
                    DispatchQueue.main.async {
                        SentrySDK.capture(error: error) { scope in
                            scope.setExtra(value: "SwapViewController row 584", key: "context")
                        }
                    }
                }
            }
        } else if status == "transaction.mempool", self.thisSwap!.swapDirection == .lightningToOnchain {
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
    
    private func handleTransactionMempool(transactionHex: String) {
        print("handleTransactionMempool called with transaction hex length: \(transactionHex.count)")
        
        // Update the swap file with the lockup transaction
        guard self.thisSwap != nil else {
            Log.info("No ongoing swap found.")
            return
        }
        
        print("Found ongoing swap with ID: \(self.thisSwap!.boltzID ?? "nil")")
        
        self.thisSwap!.lockupTx = transactionHex
        CacheManager.saveLatestSwap(self.thisSwap!)
        SwapManager.updateSwapFileWithLockupTx(swapID: self.thisSwap!.boltzID!, lockupTx: self.thisSwap!.lockupTx!)
        
        Log.info("Updated swap file with lockup transaction")
        
        // Claim onchain transaction using async function
        Task {
            do {
                Log.info("Starting Boltz claim process")
                let claimResult = try await BoltzRefund.tryBoltzClaimInternalTransactionGeneration(swapVC: self)
                print("Claim result: \(claimResult)")
                
                // Handle the result on main thread
                DispatchQueue.main.async {
                    if claimResult.success {
                        self.confirmStatusLabel.text = Language.getWord(withID: "swapstatusswapcomplete")
                        self.confirmStatusSpinner.stopAnimating()
                        self.webSocketManager?.disconnect()
                        SentrySDK.metrics.count(key: "swap.lightningtoonchain.success")
                        
                        // Add the onchain transaction to the UI
                        if let transactionId = claimResult.transactionId {
                            SwapManager.addOnchainTransactionToUI(transactionId: transactionId, swapVC: self)
                        }
                    } else {
                        self.confirmStatusLabel.text = Language.getWord(withID: "swapstatusfailed")
                    }
                }
            } catch {
                Log.info("Error claiming transaction: \(error)")
                DispatchQueue.main.async {
                    self.confirmStatusLabel.text = Language.getWord(withID: "swapstatusfailed")
                    SentrySDK.metrics.count(key: "swap.lightningtoonchain.failed")
                    SentrySDK.capture(error: error) { scope in
                        scope.setExtra(value: "SwapViewController row 839", key: "context")
                    }
                }
            }
        }
    }
    
    @IBAction func confirmStatusButtonTapped(_ sender: UIButton) {
        
        DispatchQueue.main.async {
            self.confirmStatusLabel.alpha = 0
            self.resetIcon.alpha = 0
            
            guard let swapID = self.thisSwap?.boltzID else {
                Log.info("No swap ID found in ongoing swap")
                return
            }
            print("Checking swap status for ID: \(swapID)")
            
            SwapManager.checkSwapStatus(swapID) { dictionary in
                DispatchQueue.main.async {
                    self.confirmStatusLabel.alpha = 1
                    self.resetIcon.alpha = 1
                    
                    print("Received swap status response: \(dictionary ?? [:])")
                    
                    guard dictionary != nil, let receivedStatus = dictionary!["status"] as? String else {
                        Log.info("No status received or invalid response format")
                        print("Full response: \(dictionary ?? [:])")
                        return
                    }
                    Log.info("Status received: \(receivedStatus)")

                    self.syncSuggestedSwapMarker(status: receivedStatus)
                    self.statusQuestionButton.boundString = receivedStatus
                    self.confirmStatusLabel.text = receivedStatus.userFriendlyStatus(direction: self.thisSwap!.swapDirection)
                    
                    if receivedStatus == "invoice.failedToPay" || receivedStatus == "swap.expired" || receivedStatus == "transaction.lockupFailed" {
                        Log.info("Swap failed with status: \(receivedStatus)")
                        // TODO: Add refund logic here
                    } else if receivedStatus == "transaction.confirmed" || receivedStatus == "invoice.settled" {
                        Log.info("Transaction confirmed")
                        
                        if self.thisSwap!.swapDirection == .lightningToOnchain {
                            Log.info("Processing lightning to onchain swap.")
                            if let transaction = dictionary!["transaction"] as? [String: Any] {
                                print("Transaction data: \(transaction)")
                                if let transactionHex = transaction["hex"] as? String {
                                    print("Transaction hex found, length: \(transactionHex.count)")
                                    self.handleTransactionMempool(transactionHex: transactionHex)
                                } else {
                                    Log.info("No transaction hex found in response")
                                }
                            } else {
                                Log.info("No transaction data found in response")
                                
                                // Fallback: Try to load lockup transaction from JSON file
                                Log.info("Attempting to load lockup transaction from JSON file.")
                                if let jsonLockupTx = self.loadLockupTxFromFile(swapID: swapID) {
                                    Log.info("Found lockup transaction in JSON file.")
                                    self.handleTransactionMempool(transactionHex: jsonLockupTx)
                                } else {
                                    Log.info("No lockup transaction found in JSON file either")
                                }
                            }
                        } else {
                            Log.info("Not a lightning to onchain swap.")
                        }
                    } else {
                        Log.info("Other status received: \(receivedStatus)")
                    }
                }
            }
        }
    }
    
    func didCompleteOnchainTransaction() {
        // It may take significant time (e.g. 30 minutes) for the onchain transaction to be confirmed. We need to wait for this confirmation.
        guard swapVC?.thisSwap != nil else { return }
        self.thisSwap = self.swapVC!.thisSwap!
        
        // Update label.
        self.confirmStatusLabel.text = Language.getWord(withID: "swapstatusawaitingconfirmation")
        CacheManager.saveLatestSwap(self.thisSwap!)
        
        // Start websocket.
        self.webSocketManager = WebSocketManager()
        self.webSocketManager!.delegate = self
        self.webSocketManager!.swapID = self.thisSwap!.boltzID!
        self.webSocketManager!.connect()
    }
    
    private func loadLockupTxFromFile(swapID: String) -> String? {
        print("Loading lockup transaction from file: \(swapID).json")
        
        do {
            // Get the documents directory
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let fileURL = documentsPath.appendingPathComponent("\(swapID).json")
            
            // Check if file exists
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                print("Swap file not found at: \(fileURL.path)")
                return nil
            }
            
            // Read the JSON data from file
            let jsonData = try Data(contentsOf: fileURL)
            
            // Convert JSON Data to NSDictionary
            guard let dictionary = try JSONSerialization.jsonObject(with: jsonData, options: []) as? NSDictionary else {
                Log.info("❌ Failed to parse JSON from file")
                return nil
            }
            
            // Extract lockup transaction
            if let lockupTx = dictionary["lockupTx"] as? String {
                Log.info("Found lockup transaction in JSON file")
                return lockupTx
            } else {
                Log.info("No lockup transaction found in JSON file")
                return nil
            }
            
        } catch {
            Log.info("Error loading lockup transaction from file: \(error)")
            DispatchQueue.main.async {
                SentrySDK.capture(error: error) { scope in
                    scope.setExtra(value: "SwapViewController row 1009", key: "context")
                }
            }
            return nil
        }
    }
    
    @IBAction func downloadSwapFileTapped(_ sender: UIButton) {
        self.view.endEditing(true)
        guard let ongoingSwap = self.thisSwap else { return }
        
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
            Log.info("Error loading swap details from file: \(error)")
            DispatchQueue.main.async {
                SentrySDK.capture(error: error) { scope in
                    scope.setExtra(value: "SwapViewController row 870", key: "context")
                }
            }
        }
    }
    
    @IBAction func statusQuestionTapped(_ sender: UIButton) {
        self.view.endEditing(true)
        
        guard let swapStatus = sender.boundString else {
            self.showAlert(presentingController: self, title: Language.getWord(withID: "swapquestion"), message: Language.getWord(withID: "swapquestiongeneric"), buttons: [Language.getWord(withID: "okay")], actions: nil)
            return
        }
        
        let answer:String = {
            switch swapStatus {
            case "swap.created":
                if self.thisSwap!.swapDirection == .onchainToLightning {
                    return Language.getWord(withID: "swapquestionswapcreated0")
                } else {
                    return Language.getWord(withID: "swapquestionswapcreated1")
                }
            case "invoice.set":
                return Language.getWord(withID: "swapquestionswapcreated0")
            case "transaction.mempool":
                if self.thisSwap!.swapDirection == .onchainToLightning {
                    return Language.getWord(withID: "swapquestiontransactionmempool0")
                } else {
                    return Language.getWord(withID: "swapquestioncomplete1")
                }
            case "transaction.confirmed":
                if self.thisSwap!.swapDirection == .onchainToLightning {
                    return Language.getWord(withID: "swapquestiontransactionconfirmed0")
                } else {
                    return Language.getWord(withID: "swapquestioncomplete1")
                }
            case "invoice.pending":
                return Language.getWord(withID: "swapquestioninvoicepending0")
            case "invoice.paid":
                return Language.getWord(withID: "swapquestioncomplete0")
            case "invoice.failedToPay":
                return Language.getWord(withID: "swapquestioninvoicefailedtopay0")
            case "transaction.claim.pending":
                return Language.getWord(withID: "swapquestioncomplete0")
            case "transaction.claimed":
                return Language.getWord(withID: "swapquestioncomplete0")
            case "swap.expired":
                if self.thisSwap!.swapDirection == .onchainToLightning {
                    return Language.getWord(withID: "swapquestionexpired0")
                } else {
                    return Language.getWord(withID: "swapquestionexpired1")
                }
            case "transaction.lockupFailed":
                if self.thisSwap!.swapDirection == .onchainToLightning {
                    return Language.getWord(withID: "swapquestionexpired0")
                } else {
                    return Language.getWord(withID: "swapquestionexpired1")
                }
            case "invoice.settled":
                return Language.getWord(withID: "swapquestioncomplete1")
            case "invoice.expired":
                return Language.getWord(withID: "swapquestionexpired1")
            case "transaction.failed":
                return Language.getWord(withID: "swapquestionexpired1")
            case "transaction.refunded":
                return Language.getWord(withID: "swapquestionexpired1")
            default:
                return Language.getWord(withID: "swapquestiongeneric")
            }
        }()
        
        self.showAlert(presentingController: self, title: Language.getWord(withID: "swapquestion"), message: answer, buttons: [Language.getWord(withID: "okay")], actions: nil)
    }
    
    @objc func changeColors() {
        
        self.view.backgroundColor = Colors.getColor("yelloworblue1")
        self.confirmCard.backgroundColor = Colors.getColor("yelloworblue2")
        self.confirmTopLabel.textColor = Colors.getColor("whiteoryellow")
        self.confirmDirection.backgroundColor = Colors.getColor("whiteorblue3")
        self.confirmAmount.backgroundColor = Colors.getColor("whiteorblue3")
        self.confirmFees.backgroundColor = Colors.getColor("whiteorblue3")
        self.confirmStatus.backgroundColor = Colors.getColor("whiteorblue3")
        self.confirmDirectionLabel.textColor = Colors.getColor("blackorwhite")
        self.confirmAmountLabel.textColor = Colors.getColor("blackorwhite")
        self.confirmFeesLabel.textColor = Colors.getColor("blackorwhite")
        self.confirmStatusLabel.textColor = Colors.getColor("blackorwhite")
        self.statusQuestionIcon.tintColor = Colors.getColor("blackorwhite")
        self.downloadLabel.textColor = Colors.getColor("blackorwhite")
        
        if CacheManager.darkModeIsOn() {
            self.confirmTopIcon.image = UIImage(named: "iconswap")
            self.resetIcon.image = UIImage(named: "iconresetwhite")
            self.downloadIcon.image = UIImage(named: "icondownload")
        } else {
            self.confirmTopIcon.image = UIImage(named: "iconswapwhite")
            self.resetIcon.image = UIImage(named: "iconreset")
            self.downloadIcon.image = UIImage(named: "icondownloadblack")
        }
    }
    
    func setLanguage() {
        self.titleDirection.text = Language.getWord(withID: "direction")
        self.titleAmount.text = Language.getWord(withID: "amount")
        self.titleFees.text = Language.getWord(withID: "fees")
        self.titleStatus.text = Language.getWord(withID: "status")
        self.downloadLabel.text = Language.getWord(withID: "downloadswapfile")
    }
}

extension String {
    
    func userFriendlyStatus(direction:SwapDirection) -> String {
        
        switch self {
        case "swap.created": return Language.getWord(withID: "swapstatuspreparing")
        case "invoice.set": return Language.getWord(withID: "swapstatuspreparing")
        case "transaction.mempool": return Language.getWord(withID: "swapstatusawaitingconfirmation")
        case "transaction.confirmed": if direction == .onchainToLightning {
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
        default: return self
        }
    }
}
