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
    @IBOutlet weak var headerView: UIView!
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
    
    // Heights
    @IBOutlet weak var thenViewHeight: NSLayoutConstraint!
    @IBOutlet weak var profitViewHeight: NSLayoutConstraint!
    @IBOutlet weak var descriptionViewHeight: NSLayoutConstraint!
    @IBOutlet weak var lightningIDHeight: NSLayoutConstraint!
    
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
    
    var tappedTransaction = Transaction()
    var eurValue = 0.0
    var chfValue = 0.0
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Button titles
        self.downButton.setTitle("", for: .normal)
        self.noteButton.setTitle("", for: .normal)
        self.transactionButton.setTitle("", for: .normal)
        self.descriptionButton.setTitle("", for: .normal)
        self.questionButton.setTitle("", for: .normal)
        self.lightningIdButton.setTitle("", for: .normal)
        
        // Corner radii
        headerView.layer.cornerRadius = 13
        bodyView.layer.cornerRadius = 13
        dateView.layer.cornerRadius = 7
        amountView.layer.cornerRadius = 7
        toView.layer.cornerRadius = 7
        idView.layer.cornerRadius = 7
        thenView.layer.cornerRadius = 7
        nowView.layer.cornerRadius = 7
        profitView.layer.cornerRadius = 7
        
        // Language
        self.setWords()
        
        // Transaction data
        let transactionDate = Date(timeIntervalSince1970: Double(tappedTransaction.timestamp))
        let dateFormatter = DateFormatter()
        dateFormatter.timeZone = TimeZone.current
        dateFormatter.dateFormat = "dd MMM yyyy HH:mm"
        let transactionDateString = dateFormatter.string(from: transactionDate)
        
        dateLabel.text = transactionDateString
        
        // Set sats.
        var plusSymbol = "+"
        if tappedTransaction.received - tappedTransaction.sent < 0 {
            plusSymbol = "-"
        }
        amountLabel.text = "\(plusSymbol) \(addSpacesToString(balanceValue: String(tappedTransaction.received - tappedTransaction.sent)).replacingOccurrences(of: "-", with: "")) sats"
        
        idLabel.text = tappedTransaction.id
        
        var correctValue:CGFloat = self.eurValue
        var currencySymbol = "€"
        if UserDefaults.standard.value(forKey: "currency") as? String == "CHF" {
            correctValue = self.chfValue
            currencySymbol = "CHF"
        }
        
        var transactionValue = CGFloat(tappedTransaction.received-tappedTransaction.sent)/100000000
        var balanceValue = String(Int((transactionValue*correctValue).rounded())).replacingOccurrences(of: "-", with: "")
        
        self.valueNowLabel.text = balanceValue + " " + currencySymbol
        
        if CacheManager.getTransactionNote(txid: tappedTransaction.id) != "" {
            self.noteLabel.text = CacheManager.getTransactionNote(txid: tappedTransaction.id)
            self.noteImage.alpha = 0
        } else {
            self.noteLabel.text = ""
            self.noteImage.alpha = 1
        }
        
        if tappedTransaction.isBittr == true {
            
            thenViewHeight.constant = 40
            profitViewHeight.constant = 40
            thenView.alpha = 1
            profitView.alpha = 1
            if tappedTransaction.purchaseAmount == 0 {
                // This is a lightning payment that was just received and has not yet been checked with the Bittr API.
                self.valueThenLabel.text = self.valueNowLabel.text
                self.profitLabel.text = "0 \(currencySymbol)"
            } else {
                self.valueThenLabel.text = "\(self.tappedTransaction.purchaseAmount) \(currencySymbol)"
                self.profitLabel.text = "\(Int((transactionValue*correctValue).rounded())-self.tappedTransaction.purchaseAmount) \(currencySymbol)"
            }
            
            if (profitLabel.text ?? "").contains("-") {
                self.profitView.backgroundColor = UIColor(red: 255/255, green: 237/255, blue: 237/255, alpha: 1)
                self.profitLabel.textColor = UIColor(red: 199/255, green: 142/255, blue: 142/255, alpha: 1)
            }
        } else {
            thenViewHeight.constant = 0
            profitViewHeight.constant = 0
            thenView.alpha = 0
            profitView.alpha = 0
            valueThenLabel.text = ""
            profitLabel.text = ""
        }
        
        if tappedTransaction.isLightning == true {
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
                self.feesAmount.text = "\(tappedTransaction.fee) sats"
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
            
            if tappedTransaction.isFundingTransaction {
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
            self.confirmationsAmount.text = "\(tappedTransaction.confirmations)"
            if tappedTransaction.confirmations < 1 {
                self.confirmationsAmount.text = Language.getWord(withID: "unconfirmed")
            }
            
            if tappedTransaction.received - tappedTransaction.sent < 0 {
                // Outgoing transaction.
                self.feesViewHeight.constant = 40
                self.feesView.alpha = 1
                self.feesAmount.text = "\(tappedTransaction.fee) sats"
            } else {
                // Incoming transaction.
                self.feesViewHeight.constant = 0
                self.feesView.alpha = 0
            }
            
            if tappedTransaction.lnDescription != "" {
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
        
        if tappedTransaction.isSwap {
            
            // Amount
            self.amountTitle.text = "Moved"
            self.amountLabel.text = "\(addSpacesToString(balanceValue: String(tappedTransaction.received)).replacingOccurrences(of: "-", with: "")) sats".replacingOccurrences(of: "  ", with: " ")
            
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
            self.feesAmount.text = "\(addSpacesToString(balanceValue: String(tappedTransaction.sent - tappedTransaction.received)).replacingOccurrences(of: "-", with: "")) sats".replacingOccurrences(of: "  ", with: " ")
            
            // Onchain ID
            self.idTitle.text = "Onchain ID"
            self.idLabel.text = tappedTransaction.onchainID
            
            // Lightning ID
            self.lightningIDLabel.text = tappedTransaction.lightningID
            self.lightningIDHeight.constant = 40
            self.lightningIdView.alpha = 1
            self.view.layoutIfNeeded()
            
            // Description
            //self.descriptionLabel.text = self.tappedTransaction.id
            //self.descriptionTitle.text = "Swap ID"
            self.descriptionView.alpha = 0
            NSLayoutConstraint.deactivate([self.descriptionViewHeight])
            self.descriptionViewHeight = NSLayoutConstraint(item: self.descriptionView, attribute: .height, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 0)
            NSLayoutConstraint.activate([self.descriptionViewHeight])
            
            // Current value
            transactionValue = CGFloat(tappedTransaction.received)/100000000
            balanceValue = String(Int((transactionValue*correctValue).rounded())).replacingOccurrences(of: "-", with: "")
            self.valueNowLabel.text = balanceValue + " " + currencySymbol
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
    
    func addSpacesToString(balanceValue:String) -> String {
        
        var balanceValue = balanceValue
        
        switch balanceValue.count {
        case 4:
            balanceValue = balanceValue[0] + " " + balanceValue[1..<4]
        case 5:
            balanceValue = balanceValue[0..<2] + " " + balanceValue[2..<5]
        case 6:
            balanceValue = balanceValue[0..<3] + " " + balanceValue[3..<6]
        case 7:
            balanceValue = balanceValue[0] + " " + balanceValue[1..<4] + " " + balanceValue[4..<7]
        case 8:
            balanceValue = balanceValue[0..<2] + " " + balanceValue[2..<5] + " " + balanceValue[5..<8]
        case 9:
            balanceValue = balanceValue[0..<3] + " " + balanceValue[3..<6] + " " + balanceValue[6..<9]
        default:
            balanceValue = balanceValue[0..<balanceValue.count]
        }
        
        return balanceValue
    }
    
    @IBAction func idButtonTapped(_ sender: UIButton) {
        
        var copyingText = self.tappedTransaction.id
        if self.tappedTransaction.isSwap {
            copyingText = self.tappedTransaction.onchainID
        }
        UIPasteboard.general.string = self.tappedTransaction.id
        self.showAlert(title: Language.getWord(withID: "copied"), message: copyingText, buttons: [Language.getWord(withID: "okay")], actions: nil)
    }
    
    @IBAction func descriptionButtonTapped(_ sender: UIButton) {
        
        var copyingText = self.tappedTransaction.lnDescription
        if self.tappedTransaction.isSwap {
            copyingText = self.tappedTransaction.id
        }
        
        UIPasteboard.general.string = copyingText
        self.showAlert(title: Language.getWord(withID: "copied"), message: copyingText, buttons: [Language.getWord(withID: "okay")], actions: nil)
    }
    
    @IBAction func lightningIDTapped(_ sender: UIButton) {
        
        UIPasteboard.general.string = self.tappedTransaction.lightningID
        self.showAlert(title: Language.getWord(withID: "copied"), message: self.tappedTransaction.lightningID, buttons: [Language.getWord(withID: "okay")], actions: nil)
    }
    
    @IBAction func feesQuestionButtonTapped(_ sender: UIButton) {
        
        let notificationDict:[String: Any] = ["question":Language.getWord(withID: "lightningchannelfees"),"answer":Language.getWord(withID: "lightningchannelfees2")]
        NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "question"), object: nil, userInfo: notificationDict) as Notification)
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
    }
    
}
