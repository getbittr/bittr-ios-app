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
    
    // Labels
    @IBOutlet weak var dateLabel: UILabel!
    @IBOutlet weak var amountLabel: UILabel!
    @IBOutlet weak var toLabel: UILabel!
    @IBOutlet weak var idLabel: UILabel!
    @IBOutlet weak var valueThenLabel: UILabel!
    @IBOutlet weak var valueNowLabel: UILabel!
    @IBOutlet weak var profitLabel: UILabel!
    
    // Heights
    @IBOutlet weak var thenViewHeight: NSLayoutConstraint!
    @IBOutlet weak var profitViewHeight: NSLayoutConstraint!
    
    var tappedTransaction = Transaction()
    var eurValue = 0.0
    var chfValue = 0.0
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        downButton.setTitle("", for: .normal)
        
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
        
        if tappedTransaction.received != 0 {
            amountLabel.text = "+ \(numberFormatter.number(from: "\(CGFloat(tappedTransaction.received)/100000000)".replacingOccurrences(of: ".", with: Locale.current.decimalSeparator!).replacingOccurrences(of: ",", with: Locale.current.decimalSeparator!))!.decimalValue as NSNumber) btc"
        } else {
            amountLabel.text = "- \(numberFormatter.number(from: "\(CGFloat(tappedTransaction.sent)/100000000)".replacingOccurrences(of: ".", with: Locale.current.decimalSeparator!).replacingOccurrences(of: ",", with: Locale.current.decimalSeparator!))!.decimalValue as NSNumber) btc"
        }
        
        idLabel.text = tappedTransaction.id
        
        var correctValue:CGFloat = self.eurValue
        var currencySymbol = "€"
        if UserDefaults.standard.value(forKey: "currency") as? String == "CHF" {
            correctValue = self.chfValue
            currencySymbol = "CHF"
        }
        var plusSymbol = "+"
        var transactionValue = CGFloat(tappedTransaction.received)/100000000
        if tappedTransaction.sent != 0 {
            transactionValue = CGFloat(tappedTransaction.sent)/100000000
            plusSymbol = "-"
        }
        var balanceValue = String(Int((transactionValue*correctValue).rounded()))
        
        self.valueNowLabel.text = plusSymbol + " " + balanceValue + " " + currencySymbol
        
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
    }
    
    @IBAction func downButtonTapped(_ sender: UIButton) {
        self.dismiss(animated: true)
    }
    
}
