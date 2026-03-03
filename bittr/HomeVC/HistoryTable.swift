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
            let thisTransaction = self.visibleTransactions[indexPath.row]
            
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
            
            // Year
            dateFormatter.dateFormat = "yyyy"
            if indexPath.row != 0, dateFormatter.string(from: Date(timeIntervalSince1970: Double(self.visibleTransactions[indexPath.row-1].timestamp))) != dateFormatter.string(from: Date(timeIntervalSince1970: Double(thisTransaction.timestamp))) {
                
                cell.yearLabel.text = dateFormatter.string(from: Date(timeIntervalSince1970: Double(thisTransaction.timestamp)))
                cell.yearLabel.alpha = 0.5
            } else {
                cell.yearLabel.alpha = 0
            }
            
            // Satoshis
            var plusSymbol = "+"
            if thisTransaction.received - thisTransaction.sent - thisTransaction.fee < 0 {
                plusSymbol = "-"
            }
            cell.satsLabel.text = "\(plusSymbol) \(String(thisTransaction.received - thisTransaction.sent - thisTransaction.fee).addSpaces().replacingOccurrences(of: "-", with: "")) sats".replacingOccurrences(of: "  ", with: " ")
            
            // Conversion
            let bitcoinValue = self.getCorrectBitcoinValue(coreVC: self.coreVC!)
            let transactionValue = (thisTransaction.received - thisTransaction.sent - thisTransaction.fee).inBTC()
            var balanceValue = String(Int((transactionValue*bitcoinValue.currentValue).rounded()))
            balanceValue = balanceValue.addSpaces().replacingOccurrences(of: "-", with: "")
            cell.eurosLabel.text = "\(balanceValue) \(bitcoinValue.chosenCurrency)"
            
            // Bittr
            if thisTransaction.isBittr {
                cell.showBittrStack()
                
                if thisTransaction.fiatNetAmount == 0 {
                    // No purchase amount has been received yet from the Bittr API.
                    thisTransaction.fiatNetAmount = (transactionValue*bitcoinValue.currentValue).rounded()
                }
                var correctConversion = bitcoinValue.currentValue
                let selectedCurrency = (thisTransaction.currency == "EUR") ? "€" : "CHF"
                if selectedCurrency != bitcoinValue.chosenCurrency {
                    correctConversion = (selectedCurrency == "€") ? (self.coreVC!.bittrWallet.valueInEUR ?? 0) : (self.coreVC!.bittrWallet.valueInCHF ?? 0)
                }
                let relativeGain:Int = {
                    if thisTransaction.fiatNetAmount == 0 {
                        return 0
                    } else {
                        let calculatedGain = (((transactionValue*correctConversion - thisTransaction.fiatNetAmount) / thisTransaction.fiatNetAmount) * 100).rounded()
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
                
                let currentHeight = self.coreVC?.bittrWallet.currentHeight ?? (CacheManager.getCachedData(key: "height") as? Int) ?? 0
                
                if thisTransaction.height == nil || (currentHeight - thisTransaction.height! + 1) < 1 {
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
        
        return self.visibleTransactions.count
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        
        let dateFormatter = DateFormatter()
        dateFormatter.timeZone = TimeZone.current
        dateFormatter.dateFormat = "yyyy"
        
        if indexPath.row != 0, dateFormatter.string(from: Date(timeIntervalSince1970: Double(self.visibleTransactions[indexPath.row-1].timestamp))) != dateFormatter.string(from: Date(timeIntervalSince1970: Double(self.visibleTransactions[indexPath.row].timestamp))) {
            
            return 102
        } else {
            return 75
        }
    }

}
