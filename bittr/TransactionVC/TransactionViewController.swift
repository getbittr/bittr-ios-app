//
//  TransactionViewController.swift
//  bittr
//
//  Created by Tom Melters on 30/04/2023.
//

import UIKit

class TransactionViewController: UIViewController {

    @IBOutlet weak var downButton: UIButton!
    @IBOutlet weak var bodyView: UIView!
    @IBOutlet weak var dateView: UIView!
    @IBOutlet weak var headerView: UIView!
    
    @IBOutlet weak var amountView: UIView!
    @IBOutlet weak var toView: UIView!
    @IBOutlet weak var idView: UIView!
    @IBOutlet weak var thenView: UIView!
    @IBOutlet weak var nowView: UIView!
    @IBOutlet weak var profitView: UIView!
    @IBOutlet weak var descriptionView: UIView!
    
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
    
    // Heights
    @IBOutlet weak var thenViewHeight: NSLayoutConstraint!
    @IBOutlet weak var profitViewHeight: NSLayoutConstraint!
    @IBOutlet weak var descriptionViewHeight: NSLayoutConstraint!
    
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
    
    // Buttons
    @IBOutlet weak var transactionButton: UIButton!
    @IBOutlet weak var descriptionButton: UIButton!
    
    var tappedTransaction = Transaction()
    var eurValue = 0.0
    var chfValue = 0.0
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        downButton.setTitle("", for: .normal)
        noteButton.setTitle("", for: .normal)
        transactionButton.setTitle("", for: .normal)
        descriptionButton.setTitle("", for: .normal)
        
        headerView.layer.cornerRadius = 13
        bodyView.layer.cornerRadius = 13
        dateView.layer.cornerRadius = 7
        amountView.layer.cornerRadius = 7
        toView.layer.cornerRadius = 7
        idView.layer.cornerRadius = 7
        thenView.layer.cornerRadius = 7
        nowView.layer.cornerRadius = 7
        profitView.layer.cornerRadius = 7
        
        
        let transactionDate = Date(timeIntervalSince1970: Double(tappedTransaction.timestamp))
        let dateFormatter = DateFormatter()
        dateFormatter.timeZone = TimeZone.current
        dateFormatter.dateFormat = "dd MMM yyyy HH:mm"
        let transactionDateString = dateFormatter.string(from: transactionDate)
        
        dateLabel.text = transactionDateString
        
        
        let numberFormatter = NumberFormatter()
        numberFormatter.numberStyle = .decimal
        
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
            valueThenLabel.text = "\(tappedTransaction.purchaseAmount) \(currencySymbol)"
            profitLabel.text = "\(Int((transactionValue*correctValue).rounded())-tappedTransaction.purchaseAmount) \(currencySymbol)"
            
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
            
            self.typeLabel.text = "Instant"
            self.boltImage.alpha = 0.8
            self.confirmationsViewHeight.constant = 0
            self.confirmationsView.alpha = 0
            self.feesViewHeight.constant = 0
            self.feesView.alpha = 0
            
            if self.tappedTransaction.lnDescription.trimmingCharacters(in: .whitespacesAndNewlines) != "" {
                self.descriptionLabel.text = self.tappedTransaction.lnDescription
            } else {
                self.descriptionView.alpha = 0
                NSLayoutConstraint.deactivate([self.descriptionViewHeight])
                self.descriptionViewHeight = NSLayoutConstraint(item: self.descriptionView, attribute: .height, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 0)
                NSLayoutConstraint.activate([self.descriptionViewHeight])
                self.view.layoutIfNeeded()
            }
        } else {
            // Onchain transaction
            
            self.typeLabel.text = "Regular"
            self.boltImage.alpha = 0
            self.confirmationsViewHeight.constant = 40
            self.confirmationsView.alpha = 1
            self.confirmationsAmount.text = "\(tappedTransaction.confirmations)"
            if tappedTransaction.confirmations < 1 {
                self.confirmationsAmount.text = "Unconfirmed"
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
            
            self.descriptionView.alpha = 0
            NSLayoutConstraint.deactivate([self.descriptionViewHeight])
            self.descriptionViewHeight = NSLayoutConstraint(item: self.descriptionView, attribute: .height, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 0)
            NSLayoutConstraint.activate([self.descriptionViewHeight])
            self.view.layoutIfNeeded()
        }
        
    }
    
    @IBAction func downButtonTapped(_ sender: UIButton) {
        self.dismiss(animated: true)
    }
    
    @IBAction func noteButtonTapped(_ sender: UIButton) {
        
        let alert = UIAlertController(title: "Add a note", message: "", preferredStyle: .alert)
        alert.addTextField { (textField) in
            textField.text = "\(self.noteLabel.text ?? "")"
        }
        alert.addAction(UIAlertAction(title: "Save", style: .default, handler: { (save) in
            
            let noteText = alert.textFields![0].text!
            if noteText.trimmingCharacters(in: .whitespacesAndNewlines) != "" {
                
                CacheManager.storeTransactionNote(txid: self.tappedTransaction.id, note: noteText)
                self.noteLabel.text = noteText
                self.noteImage.alpha = 0
            }
        }))
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
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
        
        UIPasteboard.general.string = self.tappedTransaction.id
        let alert = UIAlertController(title: "Copied", message: self.tappedTransaction.id, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Okay", style: .cancel, handler: nil))
        self.present(alert, animated: true)
    }
    
    @IBAction func descriptionButtonTapped(_ sender: UIButton) {
        
        UIPasteboard.general.string = self.tappedTransaction.lnDescription
        let alert = UIAlertController(title: "Copied", message: self.tappedTransaction.lnDescription, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Okay", style: .cancel, handler: nil))
        self.present(alert, animated: true)
    }
    
}
