//
//  HistoryTable.swift
//  bittr
//
//  Created by Tom Melters on 08/02/2024.
//

import UIKit

extension HomeViewController {

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        
        let cell = tableView.dequeueReusableCell(withIdentifier: "HistoryCell", for: indexPath) as? HistoryTableViewCell
        
        if let actualCell = cell {
            
            let thisTransaction = self.setTransactions[indexPath.row]
            
            // Set date.
            let transactionDate = Date(timeIntervalSince1970: Double(thisTransaction.timestamp))
            let dateFormatter = DateFormatter()
            dateFormatter.timeZone = TimeZone.current
            dateFormatter.dateFormat = "MMM dd"
            let transactionDateString = dateFormatter.string(from: transactionDate)
            
            actualCell.dayLabel.text = transactionDateString
            
            // Set sats.
            var plusSymbol = "+"
            if thisTransaction.received - thisTransaction.sent < 0 {
                plusSymbol = "-"
            }
            actualCell.satsLabel.text = "\(plusSymbol) \(addSpacesToString(balanceValue: String(thisTransaction.received - thisTransaction.sent)).replacingOccurrences(of: "-", with: "")) sats"
            /*if thisTransaction.received != 0 {
                actualCell.satsLabel.text = "+ \(addSpacesToString(balanceValue: String(thisTransaction.received))) sats"
            } else {
                actualCell.satsLabel.text = "- \(addSpacesToString(balanceValue: String(thisTransaction.sent))) sats"
            }*/
            
            // Set conversion
            // TODO: Check for Production.
            var correctValue:CGFloat = self.eurValue
            var currencySymbol = "€"
            if UserDefaults.standard.value(forKey: "currency") as? String == "CHF" {
                correctValue = self.chfValue
                currencySymbol = "CHF"
            }
            
            var transactionValue = CGFloat(thisTransaction.received - thisTransaction.sent)/100000000
            /*if transactionValue < 0 {
                //transactionValue = CGFloat(thisTransaction.sent)/100000000
                plusSymbol = "-"
            }*/
            
            var balanceValue = String(Int((transactionValue*correctValue).rounded()))
            balanceValue = addSpacesToString(balanceValue: balanceValue).replacingOccurrences(of: "-", with: "")
            
            actualCell.eurosLabel.text = balanceValue + " " + currencySymbol
            
            // Set gain label
            if thisTransaction.isBittr == true {
                actualCell.updateBoltTrailing(position: "left")
                actualCell.bittrImage.alpha = 1
                actualCell.gainView.alpha = 1
                let relativeGain:Int = Int((CGFloat(Int((transactionValue*correctValue).rounded()) - thisTransaction.purchaseAmount) / CGFloat(thisTransaction.purchaseAmount)) * 100)
                actualCell.gainLabel.text = "\(relativeGain) %"
                
                if relativeGain < 0 {
                    // Loss.
                    actualCell.arrowImage.image = UIImage(systemName: "arrow.down")
                    actualCell.arrowImage.tintColor = UIColor(red: 152/255, green: 138/255, blue: 73/255, alpha: 1)
                    actualCell.gainLabel.textColor = UIColor(red: 152/255, green: 138/255, blue: 73/255, alpha: 1)
                    actualCell.gainView.backgroundColor = UIColor(red: 248/255, green: 245/255, blue: 229/255, alpha: 1)
                } else {
                    // Profit.
                    actualCell.arrowImage.image = UIImage(systemName: "arrow.up")
                    actualCell.arrowImage.tintColor = UIColor(red: 81/255, green: 152/255, blue: 73/255, alpha: 1)
                    actualCell.gainLabel.textColor = UIColor(red: 81/255, green: 152/255, blue: 73/255, alpha: 1)
                    actualCell.gainView.backgroundColor = UIColor(red: 231/255, green: 248/255, blue: 229/255, alpha: 1)
                }
            } else {
                actualCell.updateBoltTrailing(position: "right")
                actualCell.bittrImage.alpha = 0
                actualCell.gainView.alpha = 0
                actualCell.gainLabel.text = ""
                /*actualCell.arrowImage.image = UIImage(systemName: "arrow.up")
                actualCell.arrowImage.tintColor = UIColor(red: 81/255, green: 152/255, blue: 73/255, alpha: 1)
                actualCell.gainLabel.textColor = UIColor(red: 81/255, green: 152/255, blue: 73/255, alpha: 1)
                actualCell.gainView.backgroundColor = UIColor(red: 231/255, green: 248/255, blue: 229/255, alpha: 1)*/
            }
            
            if thisTransaction.isLightning == true {
                actualCell.boltImage.alpha = 1
                
                actualCell.satsLabel.textColor = .black
                actualCell.eurosLabel.textColor = .black
            } else {
                actualCell.boltImage.alpha = 0
                
                if thisTransaction.confirmations < 1 {
                    // Unconfirmed transaction.
                    actualCell.satsLabel.textColor = UIColor(red: 177/255, green: 177/255, blue: 177/255, alpha: 1)
                    actualCell.eurosLabel.textColor = UIColor(red: 177/255, green: 177/255, blue: 177/255, alpha: 1)
                } else {
                    // Confirmed transaction
                    actualCell.satsLabel.textColor = .black
                    actualCell.eurosLabel.textColor = .black
                }
            }
            
            // Set button
            actualCell.transactionButton.tag = indexPath.row
            
            actualCell.layer.zPosition = CGFloat(indexPath.row)
            
            return actualCell
        }
        
        return UITableViewCell()
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        
        return self.setTransactions.count
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        
        return 75
    }

}
