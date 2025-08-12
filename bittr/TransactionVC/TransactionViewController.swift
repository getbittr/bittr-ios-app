//
//  TransactionViewController.swift
//  bittr
//
//  Created by Tom Melters on 30/04/2023.
//

import UIKit

class TransactionViewController: UIViewController {

    // Header view
    @IBOutlet weak var downButton: UIButton!
    @IBOutlet weak var bodyView: UIView!
    @IBOutlet weak var dateView: UIView!
    @IBOutlet weak var headerLabel: UILabel!
    
    // Views
    @IBOutlet weak var amountView: UIView!
    @IBOutlet weak var toView: UIView!
    @IBOutlet weak var idView: UIView!
    @IBOutlet weak var thenView: UIView!
    @IBOutlet weak var nowView: UIView!
    @IBOutlet weak var profitView: UIView!
    @IBOutlet weak var descriptionView: UIView!
    @IBOutlet weak var lightningIdView: UIView!
    @IBOutlet weak var swapIdView: UIView!
    
    // Titles
    @IBOutlet weak var amountTitle: UILabel!
    @IBOutlet weak var typeTitle: UILabel!
    @IBOutlet weak var idTitle: UILabel!
    @IBOutlet weak var confirmationsTitle: UILabel!
    @IBOutlet weak var feesTitle: UILabel!
    @IBOutlet weak var descriptionTitle: UILabel!
    @IBOutlet weak var valueNowTitle: UILabel!
    @IBOutlet weak var valueThenTitle: UILabel!
    @IBOutlet weak var profitTitle: UILabel!
    @IBOutlet weak var noteTitle: UILabel!
    @IBOutlet weak var swapIDLabel: UILabel!
    
    // Labels
    @IBOutlet weak var dateLabel: UILabel!
    @IBOutlet weak var amountLabel: UILabel!
    @IBOutlet weak var toLabel: UILabel!
    @IBOutlet weak var idLabel: UILabel!
    @IBOutlet weak var valueThenLabel: UILabel!
    @IBOutlet weak var valueNowLabel: UILabel!
    @IBOutlet weak var profitLabel: UILabel!
    @IBOutlet weak var descriptionLabel: UILabel!
    @IBOutlet weak var typeLabel: UILabel!
    @IBOutlet weak var boltImage: UIImageView!
    @IBOutlet weak var lightningIDLabel: UILabel!
    @IBOutlet weak var lightningIDTitle: UILabel!
    @IBOutlet weak var swapIDTitle: UILabel!
    
    // Heights
    @IBOutlet weak var thenViewHeight: NSLayoutConstraint!
    @IBOutlet weak var profitViewHeight: NSLayoutConstraint!
    @IBOutlet weak var descriptionViewHeight: NSLayoutConstraint!
    @IBOutlet weak var lightningIDHeight: NSLayoutConstraint!
    @IBOutlet weak var swapIdViewHeight: NSLayoutConstraint!
    
    // Transaction ID
    @IBOutlet weak var openUrlBox: UIView!
    @IBOutlet weak var openUrlImage: UIImageView!
    @IBOutlet weak var openUrlWidth: NSLayoutConstraint! // 5 or 35
    @IBOutlet weak var openUrlButton: UIButton!
    var tappedUrl:String?
    
    // Swap ID
    @IBOutlet weak var openSwapImage: UIImageView!
    @IBOutlet weak var openSwapButton: UIButton!
    
    // Notes
    @IBOutlet weak var noteLabel: UILabel!
    @IBOutlet weak var noteButton: UIButton!
    @IBOutlet weak var noteImage: UIImageView!
    
    // Confirmations
    @IBOutlet weak var confirmationsView: UIView!
    @IBOutlet weak var confirmationsAmount: UILabel!
    @IBOutlet weak var confirmationsViewHeight: NSLayoutConstraint!
    
    // Fees
    @IBOutlet weak var feesView: UIView!
    @IBOutlet weak var feesAmount: UILabel!
    @IBOutlet weak var feesViewHeight: NSLayoutConstraint!
    @IBOutlet weak var questionCircle: UIImageView!
    @IBOutlet weak var questionButton: UIButton!
    
    // Buttons
    @IBOutlet weak var transactionButton: UIButton!
    @IBOutlet weak var descriptionButton: UIButton!
    @IBOutlet weak var lightningIdButton: UIButton!
    @IBOutlet weak var swapIdButton: UIButton!
    
    // Variables
    var tappedTransaction = Transaction()
    var coreVC:CoreViewController?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Button titles
        self.downButton.setTitle("", for: .normal)
        self.noteButton.setTitle("", for: .normal)
        self.transactionButton.setTitle("", for: .normal)
        self.descriptionButton.setTitle("", for: .normal)
        self.questionButton.setTitle("", for: .normal)
        self.lightningIdButton.setTitle("", for: .normal)
        self.openUrlButton.setTitle("", for: .normal)
        self.swapIdButton.setTitle("", for: .normal)
        
        // Corner radii
        self.bodyView.layer.cornerRadius = 13
        self.dateView.layer.cornerRadius = 7
        self.amountView.layer.cornerRadius = 7
        self.toView.layer.cornerRadius = 7
        self.idView.layer.cornerRadius = 7
        self.thenView.layer.cornerRadius = 7
        self.nowView.layer.cornerRadius = 7
        self.profitView.layer.cornerRadius = 7
        
        // Language
        self.setWords()
        
        // Transaction data
        let transactionDate = Date(timeIntervalSince1970: Double(self.tappedTransaction.timestamp))
        let dateFormatter = DateFormatter()
        dateFormatter.timeZone = TimeZone.current
        dateFormatter.dateFormat = "dd MMM yyyy HH:mm"
        let transactionDateString = dateFormatter.string(from: transactionDate)
        
        self.dateLabel.text = transactionDateString
        
        // Set sats.
        var plusSymbol = "+"
        if self.tappedTransaction.received - self.tappedTransaction.sent < 0 {
            plusSymbol = "-"
        }
        self.amountLabel.text = "\(plusSymbol) \(String(self.tappedTransaction.received - self.tappedTransaction.sent).addSpaces().replacingOccurrences(of: "-", with: "")) sats"
        
        self.idLabel.text = self.tappedTransaction.id
        
        let bitcoinValue = self.getCorrectBitcoinValue(coreVC: self.coreVC!)
        
        var transactionValue = CGFloat(self.tappedTransaction.received-self.tappedTransaction.sent)/100000000
        var balanceValue = String(Int((transactionValue*bitcoinValue.currentValue).rounded())).replacingOccurrences(of: "-", with: "")
        
        self.valueNowLabel.text = balanceValue + " " + bitcoinValue.chosenCurrency
        
        if CacheManager.getTransactionNote(txid: self.tappedTransaction.id) != "" {
            self.noteLabel.text = CacheManager.getTransactionNote(txid: self.tappedTransaction.id)
            self.noteImage.alpha = 0
        } else {
            self.noteLabel.text = ""
            self.noteImage.alpha = 1
        }
        
        if self.tappedTransaction.isBittr == true {
            
            self.thenViewHeight.constant = 40
            self.profitViewHeight.constant = 40
            self.thenView.alpha = 1
            self.profitView.alpha = 1
            if self.tappedTransaction.purchaseAmount == 0 {
                // This is a lightning payment that was just received and has not yet been checked with the Bittr API.
                self.valueThenLabel.text = self.valueNowLabel.text
                self.profitLabel.text = "0 \(bitcoinValue.chosenCurrency)"
            } else {
                self.valueThenLabel.text = "\(self.tappedTransaction.purchaseAmount) \(bitcoinValue.chosenCurrency)"
                self.profitLabel.text = "\(Int((transactionValue*bitcoinValue.currentValue).rounded())-self.tappedTransaction.purchaseAmount) \(bitcoinValue.chosenCurrency)"
            }
            
            if (profitLabel.text ?? "").contains("-") {
                self.profitView.backgroundColor = UIColor(red: 255/255, green: 237/255, blue: 237/255, alpha: 1)
                self.profitLabel.textColor = UIColor(red: 199/255, green: 142/255, blue: 142/255, alpha: 1)
            }
        } else {
            self.thenViewHeight.constant = 0
            self.profitViewHeight.constant = 0
            self.thenView.alpha = 0
            self.profitView.alpha = 0
            self.valueThenLabel.text = ""
            self.profitLabel.text = ""
        }
        
        if self.tappedTransaction.isLightning == true {
            // Lightning transaction.
            
            self.typeLabel.text = Language.getWord(withID: "instant")
            self.boltImage.alpha = 0.8
            self.confirmationsViewHeight.constant = 0
            self.confirmationsView.alpha = 0
            self.feesViewHeight.constant = 0
            self.feesView.alpha = 0
            
            if transactionValue < 0 {
                // Outbound Lightning payment.
                self.feesViewHeight.constant = 40
                self.feesView.alpha = 1
                self.feesAmount.text = "\(self.tappedTransaction.fee) sats"
            }
            
            if self.tappedTransaction.lnDescription.trimmingCharacters(in: .whitespacesAndNewlines) != "" {
                self.descriptionLabel.text = self.tappedTransaction.lnDescription
            } else {
                self.descriptionView.alpha = 0
                NSLayoutConstraint.deactivate([self.descriptionViewHeight])
                self.descriptionViewHeight = NSLayoutConstraint(item: self.descriptionView, attribute: .height, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 0)
                NSLayoutConstraint.activate([self.descriptionViewHeight])
                self.view.layoutIfNeeded()
            }
            
            if self.tappedTransaction.isFundingTransaction {
                self.feesViewHeight.constant = 40
                self.feesView.alpha = 1
                self.feesAmount.text = "10 000 sats"
                self.questionCircle.alpha = 1
                self.questionButton.alpha = 1
            }
        } else {
            // Onchain transaction
            
            self.typeLabel.text = Language.getWord(withID: "regular")
            self.boltImage.alpha = 0
            self.confirmationsViewHeight.constant = 40
            self.confirmationsView.alpha = 1
            self.confirmationsAmount.text = "\(self.tappedTransaction.confirmations)"
            if self.tappedTransaction.confirmations < 1 {
                self.confirmationsAmount.text = Language.getWord(withID: "unconfirmed")
            }
            
            if self.tappedTransaction.received - self.tappedTransaction.sent < 0 {
                // Outgoing transaction.
                self.feesViewHeight.constant = 40
                self.feesView.alpha = 1
                self.feesAmount.text = "\(self.tappedTransaction.fee) sats"
            } else {
                // Incoming transaction.
                self.feesViewHeight.constant = 0
                self.feesView.alpha = 0
            }
            
            // Show URL button
            self.openUrlBox.alpha = 1
            self.openUrlWidth.constant = 35
            self.openUrlButton.accessibilityIdentifier = self.tappedTransaction.id
            
            if self.tappedTransaction.lnDescription != "" {
                // Swap transaction.
                self.descriptionLabel.text = self.tappedTransaction.lnDescription
            } else {
                // Normal transaction.
                self.descriptionView.alpha = 0
                NSLayoutConstraint.deactivate([self.descriptionViewHeight])
                self.descriptionViewHeight = NSLayoutConstraint(item: self.descriptionView, attribute: .height, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 0)
                NSLayoutConstraint.activate([self.descriptionViewHeight])
                self.view.layoutIfNeeded()
            }
        }
        
        if self.tappedTransaction.isSwap {
            
            // Amount
            self.amountTitle.text = "Moved"
            self.amountLabel.text = "\(String(tappedTransaction.received).addSpaces().replacingOccurrences(of: "-", with: "")) sats".replacingOccurrences(of: "  ", with: " ")
            
            // Direction
            self.typeTitle.text = "From"
            self.boltImage.alpha = 0
            if tappedTransaction.swapDirection == 0 {
                self.typeLabel.text = "Onchain to Lightning"
            } else {
                self.typeLabel.text = "Lightning to Onchain"
            }
            
            // Fees
            self.feesViewHeight.constant = 40
            self.feesView.alpha = 1
            self.feesAmount.text = "\(String(self.tappedTransaction.sent - self.tappedTransaction.received).addSpaces().replacingOccurrences(of: "-", with: "")) sats".replacingOccurrences(of: "  ", with: " ")
            
            // Onchain ID
            self.idTitle.text = "Onchain ID"
            self.idLabel.text = self.tappedTransaction.onchainID
            self.openUrlButton.accessibilityIdentifier = self.tappedTransaction.onchainID
            
            // Show URL button for swap transactions
            self.openUrlBox.alpha = 1
            self.openUrlWidth.constant = 35
            
            // Lightning ID
            self.lightningIDLabel.text = self.tappedTransaction.lightningID
            self.lightningIDHeight.constant = 40
            self.lightningIdView.alpha = 1
            self.view.layoutIfNeeded()
            
            // Swap ID
            self.swapIdView.alpha = 1
            self.swapIdViewHeight.constant = 40
            self.swapIDLabel.text = CacheManager.getSwapID(dateID: self.tappedTransaction.lnDescription) ?? "Unavailable"
            
            // Description
            self.descriptionView.alpha = 0
            NSLayoutConstraint.deactivate([self.descriptionViewHeight])
            self.descriptionViewHeight = NSLayoutConstraint(item: self.descriptionView, attribute: .height, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 0)
            NSLayoutConstraint.activate([self.descriptionViewHeight])
            
            // Current value
            transactionValue = CGFloat(self.tappedTransaction.received)/100000000
            balanceValue = String(Int((transactionValue*bitcoinValue.currentValue).rounded())).replacingOccurrences(of: "-", with: "")
            self.valueNowLabel.text = balanceValue + " " + bitcoinValue.chosenCurrency
        } else if self.tappedTransaction.lnDescription.contains("Swap ") {
            // This is an incomplete Swap transaction. Either onchain or lightning.
            
            // Swap ID
            self.swapIdView.alpha = 1
            self.swapIdViewHeight.constant = 40
            self.swapIDLabel.text = CacheManager.getSwapID(dateID: self.tappedTransaction.lnDescription) ?? "Unavailable"
            
            // Description
            self.descriptionView.alpha = 0
            NSLayoutConstraint.deactivate([self.descriptionViewHeight])
            self.descriptionViewHeight = NSLayoutConstraint(item: self.descriptionView, attribute: .height, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 0)
            NSLayoutConstraint.activate([self.descriptionViewHeight])
            
            // Swap direction
            if self.tappedTransaction.lnDescription.contains("onchain to lightning") {
                self.tappedTransaction.swapDirection = 0
            } else {
                self.tappedTransaction.swapDirection = 1
            }
        }
        
        self.changeColors()
    }
    
    @IBAction func downButtonTapped(_ sender: UIButton) {
        self.dismiss(animated: true)
    }
    
    @IBAction func noteButtonTapped(_ sender: UIButton) {
        
        let alert = UIAlertController(title: Language.getWord(withID: "addanote"), message: "", preferredStyle: .alert)
        alert.addTextField { (textField) in
            textField.text = "\(self.noteLabel.text ?? "")"
        }
        alert.addAction(UIAlertAction(title: Language.getWord(withID: "save"), style: .default, handler: { (save) in
            
            let noteText = alert.textFields![0].text!
            if noteText.trimmingCharacters(in: .whitespacesAndNewlines) != "" {
                
                CacheManager.storeTransactionNote(txid: self.tappedTransaction.id, note: noteText)
                self.noteLabel.text = noteText
                self.noteImage.alpha = 0
            }
        }))
        alert.addAction(UIAlertAction(title: Language.getWord(withID: "cancel"), style: .cancel, handler: nil))
        self.present(alert, animated: true)
    }
    
    @IBAction func idButtonTapped(_ sender: UIButton) {
        
        var copyingText = self.tappedTransaction.id
        if self.tappedTransaction.isSwap {
            copyingText = self.tappedTransaction.onchainID
        }
        UIPasteboard.general.string = copyingText
        self.showAlert(presentingController: self, title: Language.getWord(withID: "copied"), message: copyingText, buttons: [Language.getWord(withID: "okay")], actions: nil)
    }
    
    @IBAction func descriptionButtonTapped(_ sender: UIButton) {
        
        var copyingText = self.tappedTransaction.lnDescription
        if self.tappedTransaction.isSwap {
            copyingText = self.tappedTransaction.id
        }
        
        UIPasteboard.general.string = copyingText
        self.showAlert(presentingController: self, title: Language.getWord(withID: "copied"), message: copyingText, buttons: [Language.getWord(withID: "okay")], actions: nil)
    }
    
    @IBAction func lightningIDTapped(_ sender: UIButton) {
        
        UIPasteboard.general.string = self.tappedTransaction.lightningID
        self.showAlert(presentingController: self, title: Language.getWord(withID: "copied"), message: self.tappedTransaction.lightningID, buttons: [Language.getWord(withID: "okay")], actions: nil)
    }
    
    @IBAction func feesQuestionButtonTapped(_ sender: UIButton) {
        self.coreVC!.launchQuestion(question: Language.getWord(withID: "lightningchannelfees"), answer: Language.getWord(withID: "lightningchannelfees2"), type: nil)
    }
    
    @IBAction func openUrlButtonTapped(_ sender: UIButton) {
        if let thisUrl = sender.accessibilityIdentifier {
            self.tappedUrl = "https://mempool.space/tx/\(thisUrl)?mode=details"
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
                if self.tappedTransaction.isSwap {
                    tappedSwap.satoshisAmount = self.tappedTransaction.received
                    tappedSwap.onchainFees = self.tappedTransaction.sent - self.tappedTransaction.received
                    tappedSwap.lightningFees = 0
                } else {
                    tappedSwap.satoshisAmount = self.tappedTransaction.sent - self.tappedTransaction.fee
                    tappedSwap.onchainFees = 0
                    tappedSwap.lightningFees = self.tappedTransaction.fee
                }
                tappedSwap.onchainToLightning = true
                if self.tappedTransaction.swapDirection == 1 {
                    tappedSwap.onchainToLightning = false
                }
                swapVC.tappedSwapTransaction = tappedSwap
            }
        }
    }
    
    func changeColors() {
        
        // Card
        self.view.backgroundColor = Colors.getColor("yelloworblue1")
        self.bodyView.backgroundColor = Colors.getColor("whiteorblue2")
        
        // Date
        self.dateView.backgroundColor = Colors.getColor("grey1orblue3")
        self.dateLabel.textColor = Colors.getColor("blackorwhite")
        
        // Amount
        self.amountTitle.textColor = Colors.getColor("blackoryellow")
        self.amountLabel.textColor = Colors.getColor("blackorwhite")
        
        // Type
        self.typeTitle.textColor = Colors.getColor("blackoryellow")
        self.typeLabel.textColor = Colors.getColor("blackorwhite")
        self.boltImage.tintColor = Colors.getColor("blackorwhite")
        
        // ID
        self.idTitle.textColor = Colors.getColor("blackoryellow")
        self.idLabel.textColor = Colors.getColor("blackorwhite")
        
        // Description
        self.descriptionTitle.textColor = Colors.getColor("blackoryellow")
        self.descriptionLabel.textColor = Colors.getColor("blackorwhite")
        
        // Swap ID
        self.swapIDTitle.textColor = Colors.getColor("blackoryellow")
        self.swapIDLabel.textColor = Colors.getColor("blackorwhite")
        
        // Fees
        self.feesTitle.textColor = Colors.getColor("blackoryellow")
        self.feesAmount.textColor = Colors.getColor("blackorwhite")
        self.questionCircle.tintColor = Colors.getColor("blackorwhite")
        
        // Confirmations
        self.confirmationsTitle.textColor = Colors.getColor("blackoryellow")
        self.confirmationsAmount.textColor = Colors.getColor("blackorwhite")
        
        // Current value
        self.valueNowTitle.textColor = Colors.getColor("blackoryellow")
        self.valueNowLabel.textColor = Colors.getColor("blackorwhite")
        
        // Purchase value
        self.valueThenTitle.textColor = Colors.getColor("blackoryellow")
        self.valueThenLabel.textColor = Colors.getColor("blackorwhite")
        
        // Lightning ID
        self.lightningIDTitle.textColor = Colors.getColor("blackoryellow")
        self.lightningIDLabel.textColor = Colors.getColor("blackorwhite")
        
        // Profit
        self.profitTitle.textColor = Colors.getColor("blackoryellow")
        if (self.profitLabel.text ?? "").contains("-") {
            self.profitView.backgroundColor = Colors.getColor("lossbackground")
            self.profitLabel.textColor = Colors.getColor("losstext")
        } else {
            self.profitView.backgroundColor = Colors.getColor("profitbackground")
            self.profitLabel.textColor = Colors.getColor("profittext")
        }
        
        // Note
        self.noteTitle.textColor = Colors.getColor("blackoryellow")
        self.noteLabel.textColor = Colors.getColor("blackorwhite")
        self.noteImage.tintColor = Colors.getColor("grey2orwhite")
        self.openUrlImage.tintColor = Colors.getColor("grey2orwhite")
        self.openSwapImage.tintColor = Colors.getColor("grey2orwhite")
    }
    
}
