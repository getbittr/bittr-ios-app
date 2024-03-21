//
//  LightningPaymentViewController.swift
//  bittr
//
//  Created by Tom Melters on 23/12/2023.
//

import UIKit

class LightningPaymentViewController: UIViewController {

    @IBOutlet weak var downButton: UIButton!
    @IBOutlet weak var headerView: UIView!
    
    @IBOutlet weak var bodyView: UIView!
    @IBOutlet weak var dateView: UIView!
    @IBOutlet weak var dateLabel: UILabel!
    @IBOutlet weak var amountLabel: UILabel!
    @IBOutlet weak var descriptionLabel: UILabel!
    @IBOutlet weak var descriptionButton: UIButton!
    @IBOutlet weak var nowLabel: UILabel!
    
    var receivedTransaction:Transaction?
    var eurValue:CGFloat = 0.0
    var chfValue:CGFloat = 0.0
    
    override func viewDidLoad() {
        super.viewDidLoad()

        downButton.setTitle("", for: .normal)
        descriptionButton.setTitle("", for: .normal)
        headerView.layer.cornerRadius = 13
        bodyView.layer.cornerRadius = 13
        dateView.layer.cornerRadius = 7
        
        if let actualTransaction = self.receivedTransaction {
            
            let transactionDate = Date(timeIntervalSince1970: Double(actualTransaction.timestamp))
            let dateFormatter = DateFormatter()
            dateFormatter.timeZone = TimeZone.current
            dateFormatter.dateFormat = "dd MMM yyyy HH:mm"
            let transactionDateString = dateFormatter.string(from: transactionDate)
            
            dateLabel.text = transactionDateString
            
            let numberFormatter = NumberFormatter()
            numberFormatter.numberStyle = .decimal
            
            // Set sats.
            var plusSymbol = "+"
            if actualTransaction.received - actualTransaction.sent < 0 {
                plusSymbol = "-"
            }
            amountLabel.text = "\(plusSymbol) \(addSpacesToString(balanceValue: String(actualTransaction.received - actualTransaction.sent)).replacingOccurrences(of: "-", with: "")) sats"
            
            var correctValue:CGFloat = self.eurValue
            var currencySymbol = "€"
            if UserDefaults.standard.value(forKey: "currency") as? String == "CHF" {
                correctValue = self.chfValue
                currencySymbol = "CHF"
            }
            
            var transactionValue = CGFloat(actualTransaction.received-actualTransaction.sent)/100000000
            var balanceValue = String(Int((transactionValue*correctValue).rounded())).replacingOccurrences(of: "-", with: "")
            
            self.nowLabel.text = balanceValue + " " + currencySymbol
            
            self.descriptionLabel.text = actualTransaction.lnDescription
        }
    }
    
    @IBAction func downButtonTapped(_ sender: UIButton) {
        self.dismiss(animated: true)
    }
    
    @IBAction func descriptionButtonTapped(_ sender: UIButton) {
        
        if let actualTransaction = self.receivedTransaction {
            
            UIPasteboard.general.string = actualTransaction.lnDescription
            let alert = UIAlertController(title: "Copied", message: actualTransaction.lnDescription, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Okay", style: .cancel, handler: nil))
            self.present(alert, animated: true)
        }
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
