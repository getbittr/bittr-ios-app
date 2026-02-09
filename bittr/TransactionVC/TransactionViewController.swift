//
//  TransactionViewController.swift
//  bittr
//
//  Created by Tom Melters on 30/04/2023.
//

import UIKit

class TransactionViewController: UIViewController {
    
    // Yellow card
    @IBOutlet weak var yellowCard: UIView!
    
    // Date stack
    @IBOutlet weak var labelDate: UILabel!
    
    // Amount stack
    @IBOutlet weak var cardAmount: UIView!
    @IBOutlet weak var titleAmount: UILabel!
    @IBOutlet weak var labelAmount: UILabel!
    
    // Type stack
    @IBOutlet weak var cardType: UIView!
    @IBOutlet weak var titleType: UILabel!
    @IBOutlet weak var labelType: UILabel!
    @IBOutlet weak var typeBoltImage: UIImageView!
    
    // Swap stack
    @IBOutlet weak var swapStack: UIView!
    @IBOutlet weak var swapStackHeight: NSLayoutConstraint! // 0 or 87
    @IBOutlet weak var cardSwapId: UIView!
    @IBOutlet weak var titleSwapId: UILabel!
    @IBOutlet weak var labelSwapId: UILabel!
    @IBOutlet weak var titleSwapStatus: UILabel!
    @IBOutlet weak var labelSwapStatus: UILabel!
    @IBOutlet weak var swapArrowImage: UIImageView!
    @IBOutlet weak var buttonSwapStatus: UIButton!
    
    // Fees stack
    @IBOutlet weak var feesStack: UIView!
    @IBOutlet weak var feesStackHeight: NSLayoutConstraint!
    @IBOutlet weak var cardFees: UIView!
    @IBOutlet weak var titleFees: UILabel!
    @IBOutlet weak var labelFees: UILabel!
    
    // Confirmations stack
    @IBOutlet weak var confirmationsStack: UIView!
    @IBOutlet weak var confirmationsStackHeight: NSLayoutConstraint!
    @IBOutlet weak var cardConfirmations: UIView!
    @IBOutlet weak var titleConfirmations: UILabel!
    @IBOutlet weak var labelConfirmations: UILabel!
    
    // Description stack
    @IBOutlet weak var descriptionStack: UIView!
    @IBOutlet weak var descriptionStackHeight: NSLayoutConstraint!
    @IBOutlet weak var cardDescription: UIView!
    @IBOutlet weak var titleDescription: UILabel!
    @IBOutlet weak var labelDescription: UILabel!
    @IBOutlet weak var buttonDescription: UIButton!
    
    // IDs stack
    @IBOutlet weak var cardTopId: UIView!
    @IBOutlet weak var titleTopId: UILabel!
    @IBOutlet weak var labelTopId: UILabel!
    @IBOutlet weak var urlStackTopId: UIView!
    @IBOutlet weak var urlStackTopIdWidth: NSLayoutConstraint!
    @IBOutlet weak var urlButtonTopId: UIButton!
    @IBOutlet weak var urlImageTopId: UIImageView!
    @IBOutlet weak var copyButtonTopId: UIButton!
    @IBOutlet weak var bottomIdStack: UIView!
    @IBOutlet weak var bottomIdStackHeight: NSLayoutConstraint!
    @IBOutlet weak var titleBottomId: UILabel!
    @IBOutlet weak var labelBottomId: UILabel!
    @IBOutlet weak var urlStackBottomId: UIView!
    @IBOutlet weak var urlStackBottomIdWidth: NSLayoutConstraint!
    @IBOutlet weak var urlButtonBottomId: UIButton!
    @IBOutlet weak var urlImageBottomId: UIImageView!
    @IBOutlet weak var copyButtonBottomId: UIButton!
    var tappedUrl:String?
    
    // Value stack
    @IBOutlet weak var cardValue: UIView!
    @IBOutlet weak var titleCurrentValue: UILabel!
    @IBOutlet weak var labelCurrentValue: UILabel!
    @IBOutlet weak var profitStack: UIView!
    @IBOutlet weak var profitStackHeight: NSLayoutConstraint!
    @IBOutlet weak var titlePurchaseValue: UILabel!
    @IBOutlet weak var labelPurchaseValue: UILabel!
    @IBOutlet weak var titleProfit: UILabel!
    @IBOutlet weak var labelProfit: UILabel!
    
    // Bittr fees stack
    @IBOutlet weak var bittrFeesStack: UIView!
    @IBOutlet weak var bittrFeesStackHeight: NSLayoutConstraint!
    @IBOutlet weak var cardBittrFees: UIView!
    @IBOutlet weak var transferFeesStack: UIView!
    @IBOutlet weak var titleTransferFee: UILabel!
    @IBOutlet weak var labelTransferFee: UILabel!
    @IBOutlet weak var bittrFeeStack: UIView!
    @IBOutlet weak var titleBittrFee: UILabel!
    @IBOutlet weak var labelBittrFee: UILabel!
    @IBOutlet weak var surchargeStack: UIView!
    @IBOutlet weak var surchargeStackHeight: NSLayoutConstraint!
    @IBOutlet weak var titleSurcharge: UILabel!
    @IBOutlet weak var labelSurcharge: UILabel!
    
    // Note stack
    @IBOutlet weak var noteStack: UIView!
    @IBOutlet weak var noteStackHeight: NSLayoutConstraint!
    @IBOutlet weak var cardNote: UIView!
    @IBOutlet weak var titleNote: UILabel!
    @IBOutlet weak var labelNote: UILabel!
    @IBOutlet weak var buttonNote: UIButton!
    
    // Add a note stack
    @IBOutlet weak var addANoteStack: UIView!
    @IBOutlet weak var addANoteStackHeight: NSLayoutConstraint!
    @IBOutlet weak var imageAddANote: UIImageView!
    @IBOutlet weak var titleAddANote: UILabel!
    @IBOutlet weak var buttonAddANote: UIButton!
    
    // Variables
    var tappedTransaction = Transaction()
    var coreVC:CoreViewController?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Button titles
        self.buttonSwapStatus.setTitle("", for: .normal)
        self.buttonDescription.setTitle("", for: .normal)
        self.copyButtonTopId.setTitle("", for: .normal)
        self.copyButtonBottomId.setTitle("", for: .normal)
        self.urlButtonTopId.setTitle("", for: .normal)
        self.urlButtonBottomId.setTitle("", for: .normal)
        self.buttonNote.setTitle("", for: .normal)
        self.buttonAddANote.setTitle("", for: .normal)
        
        // Yellow card styling
        self.yellowCard.setShadow()
        
        // Corner radii
        self.yellowCard.layer.cornerRadius = 13
        self.cardAmount.layer.cornerRadius = 8
        self.cardType.layer.cornerRadius = 8
        self.cardSwapId.layer.cornerRadius = 8
        self.cardFees.layer.cornerRadius = 8
        self.cardConfirmations.layer.cornerRadius = 8
        self.cardDescription.layer.cornerRadius = 8
        self.cardTopId.layer.cornerRadius = 8
        self.cardValue.layer.cornerRadius = 8
        self.cardBittrFees.layer.cornerRadius = 8
        self.cardNote.layer.cornerRadius = 8
        
        // Language
        self.setWords()
        self.changeColors()
        self.addHeader(iconLight: "iconpiggywhite", iconDark: "iconpiggyyellow", title: Language.getWord(withID: "transaction"))
        self.setTransactionData()
    }
    
    func setTransactionData() {
        
        // Date
        let transactionDate = Date(timeIntervalSince1970: Double(self.tappedTransaction.timestamp))
        let dateFormatter = DateFormatter()
        dateFormatter.timeZone = TimeZone.current
        dateFormatter.dateFormat = "dd MMM yyyy HH:mm"
        var transactionDateString = dateFormatter.string(from: transactionDate)
        if transactionDateString.first == "0" {
            transactionDateString = String(transactionDateString.dropFirst())
        }
        self.labelDate.text = transactionDateString
        
        // Amount
        if self.tappedTransaction.isSwap {
            if self.tappedTransaction.swapStatus == .succeeded {
                self.labelAmount.text = "\(String(self.tappedTransaction.received).addSpaces().replacingOccurrences(of: "-", with: "")) sats".replacingOccurrences(of: "  ", with: " ")
            } else if self.tappedTransaction.swapStatus == .pending {
                if let swapID = CacheManager.getSwapID(dateID: self.tappedTransaction.lnDescription), let swapDictionary = SwapManager.loadSwapDetailsFromFile(swapID: swapID) {
                    let convertedSwap = CacheManager.dictionaryToSwap(swapDictionary)
                    self.labelAmount.text = "\(convertedSwap.satoshisAmount)".addSpaces() + " sats"
                } else {
                    self.labelAmount.text = "\(String(self.tappedTransaction.received - self.tappedTransaction.sent).addSpaces().replacingOccurrences(of: "-", with: "")) sats".replacingOccurrences(of: "  ", with: " ")
                }
            } else if self.tappedTransaction.swapDirection == .onchainToLightning {
                // Normal swap has failed.
                self.labelAmount.text = "0 sats"
            }
        } else {
            var plusSymbol = "+"
            if (self.tappedTransaction.received - self.tappedTransaction.sent) < 0 {
                plusSymbol = "-"
            }
            self.labelAmount.text = "\(plusSymbol) \(String(self.tappedTransaction.received - self.tappedTransaction.sent).addSpaces().replacingOccurrences(of: "-", with: "")) sats".replacingOccurrences(of: "  ", with: " ")
        }
        
        // Type
        if self.tappedTransaction.isSwap {
            switch self.tappedTransaction.swapDirection {
            case .onchainToLightning:
                self.labelType.text = Language.getWord(withID: "onchaintolightning")
            case .lightningToOnchain:
                self.labelType.text = Language.getWord(withID: "lightningtoonchain")
            }
        } else {
            if self.tappedTransaction.isLightning {
                self.labelType.text = Language.getWord(withID: "instant")
                self.typeBoltImage.alpha = 0.8
            } else {
                self.labelType.text = Language.getWord(withID: "regular")
            }
        }
        
        // Swap ID and status
        if self.tappedTransaction.isSwap {
            // Show swap stack
            self.swapStack.alpha = 1
            self.swapStackHeight.constant = 87
            
            // Swap ID
            self.labelSwapId.text = CacheManager.getSwapID(dateID: self.tappedTransaction.lnDescription) ?? "Unavailable"
            
            // Swap status
            switch self.tappedTransaction.swapStatus {
            case .succeeded:
                self.labelSwapStatus.text = Language.getWord(withID: "swapsucceeded")
            case .pending:
                self.labelSwapStatus.text = Language.getWord(withID: "swappending")
            case .failed:
                self.labelSwapStatus.text = Language.getWord(withID: "swapfailed")
            }
        }
        
        // Fees
        if self.tappedTransaction.isSwap {
            self.feesStackHeight.constant = 55
            self.feesStack.alpha = 1
            if self.tappedTransaction.swapStatus != .pending {
                // Completed or failed swap.
                self.labelFees.text = "\(String(self.tappedTransaction.sent - self.tappedTransaction.received).addSpaces().replacingOccurrences(of: "-", with: "")) sats".replacingOccurrences(of: "  ", with: " ")
            } else {
                // Pending swap.
                if let swapID = CacheManager.getSwapID(dateID: self.tappedTransaction.lnDescription), let swapDictionary = SwapManager.loadSwapDetailsFromFile(swapID: swapID) {
                    let convertedSwap = CacheManager.dictionaryToSwap(swapDictionary)
                    self.labelFees.text = "\(self.tappedTransaction.sent - self.tappedTransaction.received - convertedSwap.satoshisAmount)".addSpaces() + " sats"
                } else {
                    self.labelFees.text = "0 sats"
                }
            }
        } else if (self.tappedTransaction.received-self.tappedTransaction.sent-self.tappedTransaction.fee) < 0 {
            // Outbound transaction.
            self.feesStackHeight.constant = 55
            self.feesStack.alpha = 1
            self.labelFees.text = "\(String(self.tappedTransaction.fee).addSpaces().replacingOccurrences(of: "-", with: "")) sats".replacingOccurrences(of: "  ", with: " ")
        }
        
        // Confirmations
        if !self.tappedTransaction.isLightning, !self.tappedTransaction.isSwap {
            // Onchain transaction.
            self.confirmationsStackHeight.constant = 55
            self.confirmationsStack.alpha = 1
            
            let currentHeight = self.coreVC!.bittrWallet.currentHeight ?? (CacheManager.getCachedData(key: "height") as? Int) ?? 0
            
            if self.tappedTransaction.height == nil || (currentHeight - self.tappedTransaction.height! + 1) < 1 {
                // Unconfirmed transaction.
                self.labelConfirmations.text = Language.getWord(withID: "unconfirmed")
            } else {
                // Confirmed transaction.
                self.labelConfirmations.text = "\(currentHeight - self.tappedTransaction.height! + 1)".addSpaces()
            }
        }
        
        // Description
        if self.tappedTransaction.lnDescription.trimmingCharacters(in: .whitespacesAndNewlines) != "", !self.tappedTransaction.isSwap {
            
            self.labelDescription.text = self.tappedTransaction.lnDescription
            NSLayoutConstraint.deactivate([self.descriptionStackHeight])
            self.descriptionStackHeight = NSLayoutConstraint(item: self.descriptionStack, attribute: .height, relatedBy: .greaterThanOrEqual, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 0)
            NSLayoutConstraint.activate([self.descriptionStackHeight])
            self.view.layoutIfNeeded()
            self.descriptionStack.alpha = 1
        }
        
        // IDs
        if self.tappedTransaction.isSwap {
            self.bottomIdStack.alpha = 1
            self.bottomIdStackHeight.constant = 29
            if self.tappedTransaction.swapDirection == .onchainToLightning {
                // Top ID
                self.titleTopId.text = Language.getWord(withID: "onchainid")
                self.labelTopId.text = self.tappedTransaction.onchainID
                self.copyButtonTopId.accessibilityIdentifier = self.tappedTransaction.onchainID
                // Top URL
                self.urlStackTopId.alpha = 1
                self.urlStackTopIdWidth.constant = 22
                self.urlButtonTopId.accessibilityIdentifier = self.tappedTransaction.onchainID
                // Bottom ID and URL
                switch self.tappedTransaction.swapStatus {
                case .succeeded:
                    self.titleBottomId.text = Language.getWord(withID: "lightningid")
                    self.labelBottomId.text = self.tappedTransaction.lightningID
                    self.copyButtonBottomId.accessibilityIdentifier = self.tappedTransaction.lightningID
                case .pending:
                    self.titleBottomId.text = Language.getWord(withID: "lightningid")
                    self.labelBottomId.text = Language.getWord(withID: "expecting")
                case .failed:
                    self.titleBottomId.text = Language.getWord(withID: "refundid")
                    self.labelBottomId.text = self.tappedTransaction.lightningID
                    self.copyButtonBottomId.accessibilityIdentifier = self.tappedTransaction.lightningID
                    self.urlStackBottomId.alpha = 1
                    self.urlStackBottomIdWidth.constant = 22
                    self.urlButtonBottomId.accessibilityIdentifier = self.tappedTransaction.lightningID
                }
            } else if self.tappedTransaction.swapDirection == .lightningToOnchain {
                // Top ID
                self.titleTopId.text = Language.getWord(withID: "lightningid")
                self.labelTopId.text = self.tappedTransaction.lightningID
                self.copyButtonTopId.accessibilityIdentifier = self.tappedTransaction.lightningID
                // Bottom ID and URL
                switch self.tappedTransaction.swapStatus {
                case .succeeded:
                    self.titleBottomId.text = Language.getWord(withID: "onchainid")
                    self.labelBottomId.text = self.tappedTransaction.onchainID
                    self.copyButtonBottomId.accessibilityIdentifier = self.tappedTransaction.onchainID
                    self.urlStackBottomId.alpha = 1
                    self.urlStackBottomIdWidth.constant = 22
                    self.urlButtonBottomId.accessibilityIdentifier = self.tappedTransaction.onchainID
                case .pending:
                    self.titleBottomId.text = Language.getWord(withID: "onchainid")
                    self.labelBottomId.text = Language.getWord(withID: "expecting")
                case .failed:
                    self.bottomIdStack.alpha = 0
                    self.bottomIdStackHeight.constant = 0
                }
            }
        } else {
            // Onchain or Lightning transaction.
            self.titleTopId.text = Language.getWord(withID: "id")
            self.labelTopId.text = self.tappedTransaction.id
            self.copyButtonTopId.accessibilityIdentifier = self.tappedTransaction.id
            if !self.tappedTransaction.isLightning {
                self.urlStackTopId.alpha = 1
                self.urlStackTopIdWidth.constant = 22
                self.urlButtonTopId.accessibilityIdentifier = self.tappedTransaction.id
            }
        }
        
        // Value
        let bitcoinValue = self.getCorrectBitcoinValue(coreVC: self.coreVC!)
        if self.tappedTransaction.isSwap {
            // Swap.
            let transactionValue = (self.tappedTransaction.sent - self.tappedTransaction.received).inBTC()
            let balanceValue = String(transactionValue*bitcoinValue.currentValue).replacingOccurrences(of: "-", with: "").addSpaces()
            self.labelCurrentValue.text = balanceValue + " " + bitcoinValue.chosenCurrency
        } else {
            // Onchain or Lightning transaction.
            let transactionValue = (self.tappedTransaction.received-self.tappedTransaction.sent-self.tappedTransaction.fee).inBTC()
            let balanceValue = String(transactionValue*bitcoinValue.currentValue).replacingOccurrences(of: "-", with: "").addSpaces()
            self.labelCurrentValue.text = balanceValue + " " + bitcoinValue.chosenCurrency
            
            if self.tappedTransaction.isBittr {
                self.profitStack.alpha = 1
                self.profitStackHeight.constant = 56
                
                if self.tappedTransaction.purchaseAmount == 0 {
                    // This is a lightning payment that was just received and has not yet been checked with the Bittr API.
                    self.labelPurchaseValue.text = self.labelCurrentValue.text
                    self.labelProfit.text = "0" + Locale.current.decimalSeparator! + "00 " + "\(bitcoinValue.chosenCurrency)"
                } else {
                    self.labelPurchaseValue.text = "\(self.tappedTransaction.purchaseAmount)\(Locale.current.decimalSeparator!)00".addSpaces() + " \(bitcoinValue.chosenCurrency)"
                    let profitValue = String((transactionValue*bitcoinValue.currentValue)-CGFloat(self.tappedTransaction.purchaseAmount)).addSpaces()
                    self.labelProfit.text = "\(profitValue) \(bitcoinValue.chosenCurrency)"
                }
                
                if (self.labelProfit.text ?? "").contains("-") {
                    // Loss
                    self.labelProfit.textColor = Colors.getColor("losstext")
                } else {
                    // Profit
                    self.labelProfit.textColor = Colors.getColor("profittext")
                }
            }
        }
        
        // Bittr fees
        if self.tappedTransaction.isBittr {
            
            NSLayoutConstraint.deactivate([self.bittrFeesStackHeight])
            self.bittrFeesStackHeight = NSLayoutConstraint(item: self.bittrFeesStack, attribute: .height, relatedBy: .greaterThanOrEqual, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 0)
            NSLayoutConstraint.activate([self.bittrFeesStackHeight])
            self.bittrFeesStack.alpha = 1
            
            // Transfer fee.
            self.labelTransferFee.text = "\(Int(self.tappedTransaction.transferFee.rounded()))".addSpaces() + " sats"
            
            // Currency.
            let currencySymbol:String = {
                if self.tappedTransaction.currency == "EUR" {
                    return "€"
                } else {
                    return "CHF"
                }
            }()
            
            self.labelBittrFee.text = "\(self.tappedTransaction.bittrFee.toString()) \(currencySymbol)"
            
            // Surcharge
            if self.tappedTransaction.surcharge == 0 {
                self.surchargeStackHeight.constant = 0
                self.surchargeStack.alpha = 0
            } else {
                self.labelSurcharge.text = "\(self.tappedTransaction.surcharge.toString()) \(currencySymbol)"
            }
            
        }
        
        // Note
        if CacheManager.getTransactionNote(txid: self.tappedTransaction.id) != "" {
            self.labelNote.text = CacheManager.getTransactionNote(txid: self.tappedTransaction.id)
            self.showNoteStack()
        } else {
            self.addANoteStack.alpha = 1
            self.addANoteStackHeight.constant = 45
        }
        
        self.view.layoutIfNeeded()
    }
    
    func showNoteStack() {
        self.noteStack.alpha = 1
        NSLayoutConstraint.deactivate([self.noteStackHeight])
        self.noteStackHeight = NSLayoutConstraint(item: self.noteStack, attribute: .height, relatedBy: .greaterThanOrEqual, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 0)
        NSLayoutConstraint.activate([self.noteStackHeight])
        self.addANoteStack.alpha = 0
        self.addANoteStackHeight.constant = 0
        self.view.layoutIfNeeded()
    }
    
    @IBAction func noteButtonTapped(_ sender: UIButton) {
        
        let alert = UIAlertController(title: Language.getWord(withID: "addanote"), message: "", preferredStyle: .alert)
        alert.addTextField { (textField) in
            textField.text = "\(self.labelNote.text ?? "")"
        }
        alert.addAction(UIAlertAction(title: Language.getWord(withID: "save"), style: .default, handler: { (save) in
            
            let noteText = alert.textFields![0].text!
            if noteText.trimmingCharacters(in: .whitespacesAndNewlines) != "" {
                
                CacheManager.storeTransactionNote(txid: self.tappedTransaction.id, note: noteText)
                self.labelNote.text = noteText
                self.showNoteStack()
            }
        }))
        alert.addAction(UIAlertAction(title: Language.getWord(withID: "cancel"), style: .cancel, handler: nil))
        self.present(alert, animated: true)
    }
    
    @IBAction func idButtonTapped(_ sender: UIButton) {
        
        if let thisId = sender.accessibilityIdentifier {
            UIPasteboard.general.string = thisId
            self.showAlert(presentingController: self, title: Language.getWord(withID: "copied"), message: thisId, buttons: [Language.getWord(withID: "okay")], actions: nil)
        }
    }
    
    @IBAction func descriptionButtonTapped(_ sender: UIButton) {
        
        let copyingText = self.tappedTransaction.lnDescription
        UIPasteboard.general.string = copyingText
        self.showAlert(presentingController: self, title: Language.getWord(withID: "copied"), message: copyingText, buttons: [Language.getWord(withID: "okay")], actions: nil)
    }
    
    @IBAction func lightningIDTapped(_ sender: UIButton) {
        
        UIPasteboard.general.string = self.tappedTransaction.lightningID
        self.showAlert(presentingController: self, title: Language.getWord(withID: "copied"), message: self.tappedTransaction.lightningID, buttons: [Language.getWord(withID: "okay")], actions: nil)
    }
    
    @IBAction func feesQuestionButtonTapped(_ sender: UIButton) {
        let baseMessage = Language.getWord(withID: "lightningchannelfees2")
        let dynamicMessage = baseMessage.replacingOccurrences(of: "This fee", with: "This \(Int(self.tappedTransaction.transferFee.rounded())) satoshi fee")
        self.coreVC!.launchQuestion(question: Language.getWord(withID: "lightningchannelfees"), answer: dynamicMessage, type: nil)
    }
    
    @IBAction func openUrlButtonTapped(_ sender: UIButton) {
        if let thisUrl = sender.accessibilityIdentifier {
            self.tappedUrl = "\(EnvironmentConfig.explorerURL)/tx/\(thisUrl)?mode=details"
            self.performSegue(withIdentifier: "TransactionToWebsite", sender: self)
        }
    }
    
    @IBAction func openSwapTapped(_ sender: UIButton) {
        if CacheManager.getSwapID(dateID: self.tappedTransaction.lnDescription) != nil {
            self.performSegue(withIdentifier: "TransactionToSwap", sender: self)
        }
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == "TransactionToWebsite" {
            if let websiteVC = segue.destination as? WebsiteViewController {
                if let actualTappedUrl = self.tappedUrl {
                    websiteVC.tappedUrl = actualTappedUrl
                }
            }
        } else if segue.identifier == "TransactionToSwap" {
            if let swapVC = segue.destination as? SwapViewController {
                swapVC.coreVC = self.coreVC
                let tappedSwap = Swap()
                tappedSwap.boltzID = CacheManager.getSwapID(dateID: self.tappedTransaction.lnDescription)!
                tappedSwap.satoshisAmount = self.tappedTransaction.received
                tappedSwap.onchainFees = self.tappedTransaction.sent - self.tappedTransaction.received
                tappedSwap.lightningFees = 0
                tappedSwap.swapDirection = self.tappedTransaction.swapDirection
                swapVC.tappedSwapTransaction = tappedSwap
            }
        }
    }
    
}

extension CGFloat {
    
    func toString() -> String {
        
        if self == 0 {
            return "0"
        } else {
            var string = "\(self)".fixDecimals()
            if string.split(separator: Locale.current.decimalSeparator!)[1].count == 1 {
                
                if string.split(separator: Locale.current.decimalSeparator!)[1] == "0" {
                    
                    return String(string.split(separator: Locale.current.decimalSeparator!)[0])
                } else {
                    return "\(string)0"
                }
            } else {
                return string
            }
        }
    }
}
