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
            actualCell.satsLabel.text = "\(plusSymbol) \(String(thisTransaction.received - thisTransaction.sent).addSpaces().replacingOccurrences(of: "-", with: "")) sats".replacingOccurrences(of: "  ", with: " ")
            
            // Set conversion
            let bitcoinValue = self.getCorrectBitcoinValue(coreVC: self.coreVC!)
            
            let transactionValue = CGFloat(thisTransaction.received - thisTransaction.sent)/100000000
            var balanceValue = String(Int((transactionValue*bitcoinValue.currentValue).rounded()))
            balanceValue = balanceValue.addSpaces().replacingOccurrences(of: "-", with: "")
            
            actualCell.eurosLabel.text = "\(balanceValue) \(bitcoinValue.chosenCurrency)"
            
            // Set gain label
            if thisTransaction.isBittr == true {
                actualCell.updateBoltTrailing(position: "left")
                actualCell.bittrImage.alpha = 1
                actualCell.gainView.alpha = 1
                actualCell.swapImage.alpha = 0
                if thisTransaction.purchaseAmount == 0 {
                    // This is a lightning payment that was just received and has not yet been checked with the Bittr API.
                    thisTransaction.purchaseAmount = Int((transactionValue*bitcoinValue.currentValue).rounded())
                }
                let relativeGain:Int = Int((CGFloat(Int((transactionValue*bitcoinValue.currentValue).rounded()) - thisTransaction.purchaseAmount) / CGFloat(thisTransaction.purchaseAmount)) * 100)
                actualCell.gainLabel.text = "\(relativeGain) %"
                
                if relativeGain < 0 {
                    // Loss.
                    actualCell.arrowImage.image = UIImage(systemName: "arrow.down")
                    actualCell.gainView.backgroundColor = Colors.getColor("lossbackground")
                    actualCell.arrowImage.tintColor = Colors.getColor("losstext")
                    actualCell.gainLabel.textColor = Colors.getColor("losstext")
                } else {
                    // Profit.
                    actualCell.arrowImage.image = UIImage(systemName: "arrow.up")
                    actualCell.gainView.backgroundColor = Colors.getColor("profitbackground")
                    actualCell.arrowImage.tintColor = Colors.getColor("profittext")
                    actualCell.gainLabel.textColor = Colors.getColor("profittext")
                }
            } else {
                if thisTransaction.isSwap || thisTransaction.lnDescription.contains("Swap") {
                    actualCell.swapImage.alpha = 1
                    actualCell.updateBoltTrailing(position: "middle")
                    actualCell.bittrImage.alpha = 0
                    actualCell.gainView.alpha = 0
                    actualCell.gainLabel.text = ""
                } else {
                    actualCell.updateBoltTrailing(position: "right")
                    actualCell.bittrImage.alpha = 0
                    actualCell.gainView.alpha = 0
                    actualCell.gainLabel.text = ""
                    actualCell.swapImage.alpha = 0
                }
            }
            
            if thisTransaction.isLightning == true {
                actualCell.boltImage.alpha = 1
                actualCell.satsLabel.textColor = Colors.getColor("blackorwhite")
                actualCell.eurosLabel.textColor = Colors.getColor("blackorwhite")
            } else {
                actualCell.boltImage.alpha = 0
                
                if thisTransaction.confirmations < 1 && self.coreVC?.bittrWallet.currentHeight != nil {
                    // Unconfirmed transaction.
                    actualCell.satsLabel.textColor = Colors.getColor("unconfirmed")
                    actualCell.eurosLabel.textColor = Colors.getColor("unconfirmed")
                } else {
                    // Confirmed transaction
                    actualCell.satsLabel.textColor = Colors.getColor("blackorwhite")
                    actualCell.eurosLabel.textColor = Colors.getColor("blackorwhite")
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
