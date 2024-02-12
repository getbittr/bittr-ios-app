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
    
    // Heights
    @IBOutlet weak var thenViewHeight: NSLayoutConstraint!
    @IBOutlet weak var profitViewHeight: NSLayoutConstraint!
    @IBOutlet weak var descriptionViewHeight: NSLayoutConstraint!
    
    // Notes
    @IBOutlet weak var noteLabel: UILabel!
    @IBOutlet weak var noteButton: UIButton!
    @IBOutlet weak var noteImage: UIImageView!
    
    var tappedTransaction = Transaction()
    var eurValue = 0.0
    var chfValue = 0.0
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        downButton.setTitle("", for: .normal)
        noteButton.setTitle("", for: .normal)
        
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
        
        /*var plusSymbol = "+"
        if tappedTransaction.received - tappedTransaction.sent < 0 {
            plusSymbol = "-"
        }
        amountLabel.text = "\(plusSymbol) \(String(describing: numberFormatter.number(from: "\(CGFloat(tappedTransaction.received-tappedTransaction.sent)/100000000)".replacingOccurrences(of: ".", with: Locale.current.decimalSeparator!).replacingOccurrences(of: ",", with: Locale.current.decimalSeparator!))!.decimalValue as NSNumber).replacingOccurrences(of: "-", with: "")) btc"*/
        /*if tappedTransaction.received != 0 {
            amountLabel.text = "+ \(numberFormatter.number(from: "\(CGFloat(tappedTransaction.received)/100000000)".replacingOccurrences(of: ".", with: Locale.current.decimalSeparator!).replacingOccurrences(of: ",", with: Locale.current.decimalSeparator!))!.decimalValue as NSNumber) btc"
        } else {
            amountLabel.text = "- \(numberFormatter.number(from: "\(CGFloat(tappedTransaction.sent)/100000000)".replacingOccurrences(of: ".", with: Locale.current.decimalSeparator!).replacingOccurrences(of: ",", with: Locale.current.decimalSeparator!))!.decimalValue as NSNumber) btc"
        }*/
        
        idLabel.text = tappedTransaction.id
        
        var correctValue:CGFloat = self.eurValue
        var currencySymbol = "€"
        if UserDefaults.standard.value(forKey: "currency") as? String == "CHF" {
            correctValue = self.chfValue
            currencySymbol = "CHF"
        }
        
        var transactionValue = CGFloat(tappedTransaction.received-tappedTransaction.sent)/100000000
        /*if tappedTransaction.sent != 0 {
            transactionValue = CGFloat(tappedTransaction.sent)/100000000
            plusSymbol = "-"
        }*/
        var balanceValue = String(Int((transactionValue*correctValue).rounded())).replacingOccurrences(of: "-", with: "")
        
        self.valueNowLabel.text = plusSymbol + " " + balanceValue + " " + currencySymbol
        
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
            valueThenLabel.text = "+ \(tappedTransaction.purchaseAmount) \(currencySymbol)"
            profitLabel.text = "\(Int((transactionValue*correctValue).rounded())-tappedTransaction.purchaseAmount) \(currencySymbol)"
        } else {
            thenViewHeight.constant = 0
            profitViewHeight.constant = 0
            thenView.alpha = 0
            profitView.alpha = 0
            valueThenLabel.text = ""
            profitLabel.text = ""
        }
        
        if tappedTransaction.isLightning == true {
            
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
    
}
