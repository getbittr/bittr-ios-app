//
//  HistoryTable.swift
//  bittr
//
//  Created by Tom Melters on 08/02/2024.
//

import UIKit

extension HomeViewController {

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        
        if let cell = tableView.dequeueReusableCell(withIdentifier: "HistoryCell", for: indexPath) as? HistoryTableViewCell {
            
            let thisTransaction = self.setTransactions[indexPath.row]
            
            // Set date.
            let transactionDate = Date(timeIntervalSince1970: Double(thisTransaction.timestamp))
            let dateFormatter = DateFormatter()
            dateFormatter.timeZone = TimeZone.current
            dateFormatter.dateFormat = "MMM dd"
            let transactionDateString = dateFormatter.string(from: transactionDate)
            cell.dayLabel.text = transactionDateString
            
            // Set sats.
            var plusSymbol = "+"
            if thisTransaction.received - thisTransaction.sent < 0 {
                plusSymbol = "-"
            }
            cell.satsLabel.text = "\(plusSymbol) \(String(thisTransaction.received - thisTransaction.sent).addSpaces().replacingOccurrences(of: "-", with: "")) sats".replacingOccurrences(of: "  ", with: " ")
            
            // Set conversion
            let bitcoinValue = self.getCorrectBitcoinValue(coreVC: self.coreVC!)
            let transactionValue = (thisTransaction.received - thisTransaction.sent).inBTC()
            var balanceValue = String(Int((transactionValue*bitcoinValue.currentValue).rounded()))
            balanceValue = balanceValue.addSpaces().replacingOccurrences(of: "-", with: "")
            cell.eurosLabel.text = "\(balanceValue) \(bitcoinValue.chosenCurrency)"
            
            // Set gain label
            if thisTransaction.isBittr == true {
                cell.updateBoltTrailing(position: "left")
                cell.bittrImage.alpha = 1
                cell.gainView.alpha = 1
                cell.swapImage.alpha = 0
                if thisTransaction.purchaseAmount == 0 {
                    // This is a lightning payment that was just received and has not yet been checked with the Bittr API.
                    thisTransaction.purchaseAmount = Int((transactionValue*bitcoinValue.currentValue).rounded())
                }
                let relativeGain:Int = {
                    if thisTransaction.purchaseAmount == 0 {
                        return 0
                    }
                    let calculatedGain = (CGFloat(Int((transactionValue*bitcoinValue.currentValue).rounded()) - thisTransaction.purchaseAmount) / CGFloat(thisTransaction.purchaseAmount)) * 100
                    return Int(calculatedGain.isFinite ? calculatedGain : 0)
                }()
                cell.gainLabel.text = "\(relativeGain) %"
                
                if relativeGain < 0 {
                    // Loss.
                    cell.arrowImage.image = UIImage(systemName: "arrow.down")
                    cell.gainView.backgroundColor = Colors.getColor("lossbackground")
                    cell.arrowImage.tintColor = Colors.getColor("losstext")
                    cell.gainLabel.textColor = Colors.getColor("losstext")
                } else {
                    // Profit.
                    cell.arrowImage.image = UIImage(systemName: "arrow.up")
                    cell.gainView.backgroundColor = Colors.getColor("profitbackground")
                    cell.arrowImage.tintColor = Colors.getColor("profittext")
                    cell.gainLabel.textColor = Colors.getColor("profittext")
                }
            } else {
                if thisTransaction.isSwap {
                    cell.swapImage.alpha = 1
                    cell.updateBoltTrailing(position: "middle")
                    cell.boltImage.alpha = 0
                    cell.bittrImage.alpha = 0
                    cell.gainView.alpha = 0
                    cell.gainLabel.text = ""
                    if thisTransaction.swapStatus == .succeeded {
                        cell.swapImage.image = UIImage(named: "iconswapblue")
                    } else {
                        cell.swapImage.image = UIImage(named: "iconswapgrey")
                    }
                } else {
                    cell.updateBoltTrailing(position: "right")
                    cell.bittrImage.alpha = 0
                    cell.gainView.alpha = 0
                    cell.gainLabel.text = ""
                    cell.swapImage.alpha = 0
                }
            }
            
            if thisTransaction.isLightning == true {
                if !thisTransaction.isSwap {
                    cell.boltImage.alpha = 1
                } else {
                    cell.boltImage.alpha = 0
                }
                cell.satsLabel.textColor = Colors.getColor("blackorwhite")
                cell.eurosLabel.textColor = Colors.getColor("blackorwhite")
            } else {
                cell.boltImage.alpha = 0
                
                if thisTransaction.confirmations < 1 && self.coreVC?.bittrWallet.currentHeight != nil {
                    // Unconfirmed transaction.
                    cell.satsLabel.textColor = Colors.getColor("unconfirmed")
                    cell.eurosLabel.textColor = Colors.getColor("unconfirmed")
                } else {
                    // Confirmed transaction
                    cell.satsLabel.textColor = Colors.getColor("blackorwhite")
                    cell.eurosLabel.textColor = Colors.getColor("blackorwhite")
                }
            }
            
            // Set button
            cell.transactionButton.tag = indexPath.row
            
            cell.layer.zPosition = CGFloat(indexPath.row)
            
            return cell
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
