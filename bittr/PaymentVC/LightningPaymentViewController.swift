//
//  LightningPaymentViewController.swift
//  bittr
//
//  Created by Tom Melters on 23/12/2023.
//

import UIKit
import SPConfetti

class LightningPaymentViewController: UIViewController {

    // General
    @IBOutlet weak var downButton: UIButton!
    @IBOutlet weak var headerView: UIView!
    @IBOutlet weak var headerLabel: UILabel!
    @IBOutlet weak var bodyView: UIView!
    
    // Date
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
    
    // Variables
    var receivedTransaction:Transaction?
    var coreVC:CoreViewController?
    
    @IBOutlet weak var explanationLabel: UILabel!
    @IBOutlet weak var piggyImageHeight: NSLayoutConstraint!
    @IBOutlet weak var idLabel: UILabel!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.downButton.setTitle("", for: .normal)
        self.descriptionButton.setTitle("", for: .normal)
        self.headerView.layer.cornerRadius = 13
        self.bodyView.layer.cornerRadius = 13
        self.dateView.layer.cornerRadius = 7
        
        self.changeColors()
        self.setWords()
        
        if let actualTransaction = self.receivedTransaction {
            
            let transactionDate = Date(timeIntervalSince1970: Double(actualTransaction.timestamp))
            let dateFormatter = DateFormatter()
            dateFormatter.timeZone = TimeZone.current
            dateFormatter.dateFormat = "dd MMM yyyy HH:mm"
            let transactionDateString = dateFormatter.string(from: transactionDate)
            
            self.dateLabel.text = transactionDateString
            
            // Set sats.
            var plusSymbol = "+"
            if actualTransaction.received - actualTransaction.sent < 0 {
                plusSymbol = "-"
            }
            self.amountLabel.text = "\(plusSymbol) \(String(actualTransaction.received - actualTransaction.sent).addSpaces().replacingOccurrences(of: "-", with: "")) sats"
            if actualTransaction.isSwap {
                self.amountLabel.text = "+ \(String(actualTransaction.received).addSpaces().replacingOccurrences(of: "-", with: "")) sats"
            }
            
            let bitcoinValue = self.getCorrectBitcoinValue(coreVC: self.coreVC!)
            var transactionValue = (actualTransaction.received-actualTransaction.sent).inBTC()
            if actualTransaction.isSwap {
                transactionValue = actualTransaction.received.inBTC()
            }
            var balanceValue = String(Int((transactionValue*bitcoinValue.currentValue).rounded())).replacingOccurrences(of: "-", with: "")
            
            self.nowLabel.text = balanceValue + " " + bitcoinValue.chosenCurrency
            
            if actualTransaction.isBittr {
                
                self.descriptionLabel.text = actualTransaction.lnDescription
                if actualTransaction.lnDescription == "" {
                    self.descriptionLabel.text = Language.getWord(withID: "fundingtx")
                }
            } else {
                
                self.descriptionLabel.text = actualTransaction.id
                if actualTransaction.isSwap {
                    self.descriptionLabel.text = actualTransaction.lightningID
                }
                self.explanationLabel.text = Language.getWord(withID: "newpayment")
                self.idLabel.text = Language.getWord(withID: "id")
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
            if actualTransaction.isBittr {
                SPConfettiConfiguration.particlesConfig.colors = [.red]
                SPConfetti.startAnimating(.fullWidthToDown, particles: [.heart], duration: 2)
            }
        }
    }
    
    @IBAction func descriptionButtonTapped(_ sender: UIButton) {
        
        if let actualTransaction = self.receivedTransaction {
            
            UIPasteboard.general.string = actualTransaction.lnDescription
            self.showAlert(presentingController: self, title: Language.getWord(withID: "copied"), message: actualTransaction.lnDescription, buttons: [Language.getWord(withID: "okay")], actions: nil)
        }
    }
    
    func changeColors() {
        
        self.view.backgroundColor = Colors.getColor("yelloworblue1")
        
        if CacheManager.darkModeIsOn() {
            self.bodyView.backgroundColor = Colors.getColor("whiteorblue2")
        }
        
        self.explanationLabel.textColor = Colors.getColor("blackorwhite")
        
        self.dateView.backgroundColor = Colors.getColor("grey1orblue3")
        self.dateLabel.textColor = Colors.getColor("blackorwhite")
        
        self.amountLeftLabel.textColor = Colors.getColor("blackorwhite")
        self.amountLabel.textColor = Colors.getColor("blackorwhite")
        
        self.typeLeftLabel.textColor = Colors.getColor("blackorwhite")
        self.typeLabel.textColor = Colors.getColor("blackorwhite")
        self.lightningBolt.tintColor = Colors.getColor("blackorwhite")
        
        self.idLabel.textColor = Colors.getColor("blackorwhite")
        self.descriptionLabel.textColor = Colors.getColor("blackorwhite")
        
        self.nowLabel.textColor = Colors.getColor("blackorwhite")
        self.nowLeftLabel.textColor = Colors.getColor("blackorwhite")
    }
    
    func setWords() {
        
        self.headerLabel.text = Language.getWord(withID: "success2")
        self.explanationLabel.text = Language.getWord(withID: "goodjob")
        self.amountLeftLabel.text = Language.getWord(withID: "amount")
        self.typeLeftLabel.text = Language.getWord(withID: "type")
        self.idLabel.text = Language.getWord(withID: "description")
        self.nowLeftLabel.text = Language.getWord(withID: "currentvalue")
        self.typeLabel.text = Language.getWord(withID: "instant")
    }
    
}
