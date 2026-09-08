//
//  HistoryTable.swift
//  bittr
//
//  Created by Tom Melters on 08/02/2024.
//

import UIKit

extension HomeViewController {

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        
        if indexPath.row == 0 {
            // Header cell
            guard let cell = tableView.dequeueReusableCell(withIdentifier: "HomeHeaderCell", for: indexPath) as? HomeHeaderTableViewCell else { return UITableViewCell() }
            
            cell.homeVC = self
            cell.updateLayout(topSafeArea: self.view.safeAreaInsets.top)
            cell.loadCell()
            
            return cell
        }
        
        // History cell
        guard let cell = tableView.dequeueReusableCell(withIdentifier: "HistoryCell", for: indexPath) as? HistoryTableViewCell else { return UITableViewCell() }
            
        // Transaction
        let thisTransaction = self.visibleTransactions[indexPath.row - 1]
        
        // Button
        cell.transactionButton.accessibilityElements = [thisTransaction]
        // Row-indexed test IDs so the topmost cell is always addressable as
        // ...0 (e.g. history.transactionButton0 / history.transactionAmount0).
        cell.transactionButton.accessibilityIdentifier = "\(TestID.History.transactionButton)\(indexPath.row - 1)"
        cell.satsLabel.accessibilityIdentifier = "\(TestID.History.transactionAmount)\(indexPath.row - 1)"
        
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
        if (indexPath.row - 1) != 0, dateFormatter.string(from: Date(timeIntervalSince1970: Double(self.visibleTransactions[indexPath.row-2].timestamp))) != dateFormatter.string(from: Date(timeIntervalSince1970: Double(thisTransaction.timestamp))) {
            
            cell.yearLabel.text = dateFormatter.string(from: Date(timeIntervalSince1970: Double(thisTransaction.timestamp)))
            cell.yearLabel.alpha = 0.5
            cell.cellHeight.constant = 102
        } else if indexPath.row - 1 == 0 {
            cell.yearLabel.alpha = 0
            cell.cellHeight.constant = 102
        } else {
            cell.yearLabel.alpha = 0
            cell.cellHeight.constant = 75
        }
        
        // Satoshis
        var plusSymbol = "+"
        if thisTransaction.received - thisTransaction.sent - thisTransaction.fee < 0 {
            plusSymbol = "-"
        }
        cell.satsLabel.text = "\(plusSymbol) \(String(thisTransaction.received - thisTransaction.sent - thisTransaction.fee).addSpaces().replacingOccurrences(of: "-", with: "")) sats".replacingOccurrences(of: "  ", with: " ")
        
        // Conversion
        let bitcoinValue = BitcoinManager.shared.bittrWallet.getCorrectBitcoinValue()
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
                correctConversion = (selectedCurrency == "€") ? (BitcoinManager.shared.bittrWallet.valueInEUR ?? 0) : (BitcoinManager.shared.bittrWallet.valueInCHF ?? 0)
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
            
            let currentHeight = BitcoinManager.shared.bittrWallet.currentHeight ?? CacheManager.cachedHeight ?? 0
            
            if ((thisTransaction.height == nil || (currentHeight - thisTransaction.height! + 1) < 1)) && !(thisTransaction.isSwap && thisTransaction.swapStatus != .pending) {
                // Unconfirmed transaction.
                cell.satsLabel.textColor = Colors.getColor("unconfirmed")
                cell.eurosLabel.textColor = Colors.getColor("unconfirmed")
            }
        }
        
        // Swap
        if thisTransaction.isSwap {
            cell.showSwapStack()
            cell.hideLightningStack()
            // Row-indexed test IDs so the topmost swap is addressable as
            // ...0 (e.g. history.swapComplete0 / history.swapPending0),
            // matching history.transactionButton0 above.
            if thisTransaction.swapStatus == .succeeded {
                cell.swapImage.image = UIImage(named: "iconswapblue")
                cell.swapImage.accessibilityIdentifier = "\(TestID.History.swapComplete)\(indexPath.row-1)"
            } else {
                cell.swapImage.image = UIImage(named: "iconswapgrey")
                cell.swapImage.accessibilityIdentifier = "\(TestID.History.swapPending)\(indexPath.row-1)"
            }
        } else {
            cell.hideSwapStack()
            cell.swapImage.accessibilityIdentifier = nil
        }
        
        return cell
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        
        return self.visibleTransactions.count + 1
    }
    
    // MARK: Update Year label
    func tableView(_ tableView: UITableView, didEndDisplaying cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        guard let visibleRows = tableView.indexPathsForVisibleRows, !visibleRows.isEmpty else { return }
        // Update Year label scrolling down.
        let topVisibleRow = visibleRows.map(\.row).min() ?? 0
        if indexPath.row < topVisibleRow {
            // Scrolling down vertically.
            let transactionIndex = (indexPath.row - 1) + 3
            if self.visibleTransactions.indices.contains(transactionIndex) {
                let topTransaction = self.visibleTransactions[transactionIndex]
                self.coreVC?.yearLabel.text = topTransaction.year()
            }
        }
    }
    
    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        guard let visibleRows = tableView.indexPathsForVisibleRows, !visibleRows.isEmpty else { return }
        // Update Year label scrolling up.
        let topVisibleRow = visibleRows.map(\.row).min() ?? 0
        if indexPath.row <= topVisibleRow {
            // Scrolling up vertically.
            let transactionIndex = (indexPath.row - 1) + 2
            if self.visibleTransactions.indices.contains(transactionIndex) {
                let topTransaction = self.visibleTransactions[transactionIndex]
                self.coreVC?.yearLabel.text = topTransaction.year()
            }
        }
    }
    
    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()

        let topSafeArea = view.safeAreaInsets.top
        self.homeTableView.visibleCells.forEach { cell in
            if let cell = cell as? HomeHeaderTableViewCell {
                cell.updateLayout(topSafeArea: topSafeArea)
            }
        }
    }

}
