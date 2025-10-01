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
            
            // Transaction
            let thisTransaction = self.setTransactions[indexPath.row]
            
            // Button
            cell.transactionButton.accessibilityElements = [thisTransaction]
            
            // Cell zPosition
            cell.layer.zPosition = CGFloat(indexPath.row)
            
            // Date
            let transactionDate = Date(timeIntervalSince1970: Double(thisTransaction.timestamp))
            let dateFormatter = DateFormatter()
            dateFormatter.timeZone = TimeZone.current
            dateFormatter.dateFormat = "MMM dd"
            let transactionDateString = dateFormatter.string(from: transactionDate)
            cell.dayLabel.text = transactionDateString
            
            // Satoshis
            var plusSymbol = "+"
            if thisTransaction.received - thisTransaction.sent < 0 {
                plusSymbol = "-"
            }
            cell.satsLabel.text = "\(plusSymbol) \(String(thisTransaction.received - thisTransaction.sent).addSpaces().replacingOccurrences(of: "-", with: "")) sats".replacingOccurrences(of: "  ", with: " ")
            
            // Conversion
            let bitcoinValue = self.getCorrectBitcoinValue(coreVC: self.coreVC!)
            let transactionValue = (thisTransaction.received - thisTransaction.sent).inBTC()
            var balanceValue = String(Int((transactionValue*bitcoinValue.currentValue).rounded()))
            balanceValue = balanceValue.addSpaces().replacingOccurrences(of: "-", with: "")
            cell.eurosLabel.text = "\(balanceValue) \(bitcoinValue.chosenCurrency)"
            
            // Bittr
            if thisTransaction.isBittr {
                cell.showBittrStack()
                
                if thisTransaction.purchaseAmount == 0 {
                    // No purchase amount has been received yet from the Bittr API.
                    thisTransaction.purchaseAmount = (transactionValue*bitcoinValue.currentValue).rounded()
                }
                let relativeGain:Int = {
                    if thisTransaction.purchaseAmount == 0 {
                        return 0
                    } else {
                        let calculatedGain = (CGFloat(Int((transactionValue*bitcoinValue.currentValue).rounded()) - Int(thisTransaction.purchaseAmount.rounded())) / thisTransaction.purchaseAmount) * 100
                        return Int(calculatedGain.isFinite ? calculatedGain : 0)
                    }
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
                cell.hideBittrStack()
            }
            
            // Lightning or onchain
            cell.satsLabel.textColor = Colors.getColor("blackorwhite")
            cell.eurosLabel.textColor = Colors.getColor("blackorwhite")
            if thisTransaction.isLightning {
                cell.showLightningStack()
            } else {
                cell.hideLightningStack()
                
                if thisTransaction.confirmations < 1 && self.coreVC?.bittrWallet.currentHeight != nil {
                    // Unconfirmed transaction.
                    cell.satsLabel.textColor = Colors.getColor("unconfirmed")
                    cell.eurosLabel.textColor = Colors.getColor("unconfirmed")
                }
            }
            
            // Swap
            if thisTransaction.isSwap {
                cell.showSwapStack()
                cell.hideLightningStack()
                if thisTransaction.swapStatus == .succeeded {
                    cell.swapImage.image = UIImage(named: "iconswapblue")
                } else {
                    cell.swapImage.image = UIImage(named: "iconswapgrey")
                }
            } else {
                cell.hideSwapStack()
            }
            
            return cell
        } else {
            return UITableViewCell()
        }
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        
        return self.setTransactions.count
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        
        return 75
    }

}
