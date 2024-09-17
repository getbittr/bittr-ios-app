//
//  LightningPaymentViewController.swift
//  bittr
//
//  Created by Tom Melters on 23/12/2023.
//

import UIKit
import SPConfetti

class LightningPaymentViewController: UIViewController {

    @IBOutlet weak var downButton: UIButton!
    @IBOutlet weak var headerView: UIView!
    
    @IBOutlet weak var bodyView: UIView!
    @IBOutlet weak var dateView: UIView!
    @IBOutlet weak var dateLabel: UILabel!
    
    // Amount
    @IBOutlet weak var amountLeftLabel: UILabel!
    @IBOutlet weak var amountLabel: UILabel!
    
    // Type
    @IBOutlet weak var typeLeftLabel: UILabel!
    @IBOutlet weak var typeLabel: UILabel!
    @IBOutlet weak var lightningBolt: UIImageView!
    
    // Description
    @IBOutlet weak var descriptionLabel: UILabel!
    @IBOutlet weak var descriptionButton: UIButton!
    
    // Now
    @IBOutlet weak var nowLeftLabel: UILabel!
    @IBOutlet weak var nowLabel: UILabel!
    
    var receivedTransaction:Transaction?
    var eurValue:CGFloat = 0.0
    var chfValue:CGFloat = 0.0
    
    @IBOutlet weak var explanationLabel: UILabel!
    @IBOutlet weak var piggyImageHeight: NSLayoutConstraint!
    @IBOutlet weak var idLabel: UILabel!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        downButton.setTitle("", for: .normal)
        descriptionButton.setTitle("", for: .normal)
        headerView.layer.cornerRadius = 13
        bodyView.layer.cornerRadius = 13
        dateView.layer.cornerRadius = 7
        
        self.changeColors()
        
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
            
            if actualTransaction.isBittr == true {
                
                self.descriptionLabel.text = actualTransaction.lnDescription
                if actualTransaction.lnDescription == "" {
                    self.descriptionLabel.text = "Channel funding transaction"
                }
            } else {
                
                self.descriptionLabel.text = actualTransaction.id
                self.explanationLabel.text = "You've received a new payment into your lightning channel!"
                self.idLabel.text = "ID"
                self.piggyImageHeight.constant = 0
                self.view.layoutIfNeeded()
            }
        }
    }
    
    @IBAction func downButtonTapped(_ sender: UIButton) {
        self.dismiss(animated: true)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        
        if let actualTransaction = self.receivedTransaction {
            if actualTransaction.isBittr == true {
                SPConfettiConfiguration.particlesConfig.colors = [.red]
                SPConfetti.startAnimating(.fullWidthToDown, particles: [.heart], duration: 2)
            }
        }
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
    
    func changeColors() {
        
        self.view.backgroundColor = Colors.getColor(color: "yellowandgrey")
        
        if CacheManager.darkModeIsOn() {
            self.bodyView.backgroundColor = Colors.getColor(color: "cardview")
        }
        
        self.explanationLabel.textColor = Colors.getColor(color: "black")
        
        self.dateView.backgroundColor = Colors.getColor(color: "dateview")
        self.dateLabel.textColor = Colors.getColor(color: "black")
        
        self.amountLeftLabel.textColor = Colors.getColor(color: "black")
        self.amountLabel.textColor = Colors.getColor(color: "black")
        
        self.typeLeftLabel.textColor = Colors.getColor(color: "black")
        self.typeLabel.textColor = Colors.getColor(color: "black")
        self.lightningBolt.tintColor = Colors.getColor(color: "black")
        
        self.idLabel.textColor = Colors.getColor(color: "black")
        self.descriptionLabel.textColor = Colors.getColor(color: "black")
        
        self.nowLabel.textColor = Colors.getColor(color: "black")
        self.nowLeftLabel.textColor = Colors.getColor(color: "black")
    }
    
}
