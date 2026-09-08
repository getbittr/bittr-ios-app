//
//  HomeHeaderData.swift
//  bittr
//
//  Created by Tom Melters on 9/8/26.
//

import Foundation
import UIKit

extension HomeHeaderTableViewCell {
    
    func loadCell() {
        guard let homeVC = self.homeVC else { return }
        
        if homeVC.didStartReset {
            self.hideLabels()
        }
        
        // Balance and conversion.
        self.updateBalanceLabel()
        
        // Profit.
        self.calculateProfit()
        
        // Check if conversion rates have been fetched successfully.
        if homeVC.couldNotFetchConversion {
            self.headerProblemImage.alpha = 1
        }
        
        // Stop sync status spinner
        if homeVC.coreVC!.walletHasSynced {
            self.showLabels()
        } else {
            self.headerSpinner.startAnimating()
        }
    }
    
    func showLabels() {
        self.profitView.alpha = 1
        self.balanceView.alpha = 1
        self.conversionLabel.alpha = 1
        self.headerProblemImage.alpha = 0
        self.headerSpinner.stopAnimating()
        
        guard let homeVC = self.homeVC else { return }
        self.noTransactionsLabel.alpha = (homeVC.visibleTransactions.count == 0) ? 1 : 0
    }
    
    func hideLabels() {
        
        self.noTransactionsLabel.alpha = 0
        self.profitView.alpha = 0
        self.balanceView.alpha = 0
        self.conversionLabel.alpha = 0
        self.headerProblemImage.alpha = 0
        self.headerSpinner.startAnimating()
    }
    
    func updateBalanceLabel() {
        guard let homeVC = self.homeVC else { return }
        
        // Calculate total balance
        let totalBalanceSats:Int
        if homeVC.coreVC!.walletHasSynced {
            totalBalanceSats = BitcoinManager.shared.bittrWallet.satoshisOnchain + BitcoinManager.shared.bittrWallet.satoshisLightning + BitcoinManager.shared.bittrWallet.pendingBalancesFromChannelClosures
        } else {
            totalBalanceSats = Int(CacheManager.cachedSatsBalance ?? "0") ?? 0
        }
        
        // Update cached balance.
        CacheManager.cachedSatsBalance = "\(totalBalanceSats)"
        
        let satoshis = totalBalanceSats
        let isWholeBitcoin = satoshis >= Bitcoin.satoshisPerBitcoin
        
        // Get the bitcoin amount with spaces (i.e. A.BC DEF GHI).
        let whole = satoshis / Bitcoin.satoshisPerBitcoin
        let decimals = String(format: "%08ld", satoshis % Bitcoin.satoshisPerBitcoin)
        let group1 = decimals.prefix(2)
        let group2 = decimals.dropFirst(2).prefix(3)
        let group3 = decimals.dropFirst(5)
        let grouped = "\(whole).\(group1) \(group2) \(group3)"
        
        // Distinguish dimmed and filled pieces of text.
        let dimmed:String
        let filled:String
        if isWholeBitcoin {
            // Entire text is filled.
            dimmed = ""
            filled = grouped
        } else {
            // Text is partially dimmed.
            let firstSignificant = grouped.firstIndex { $0.isNumber && $0 != "0" } ?? grouped.index(before: grouped.endIndex)
            dimmed = String(grouped[..<firstSignificant])
            filled = grouped[firstSignificant...] + " sats"
        }
        
        // Cap the label's width.
        let maximumWidth = UIScreen.main.bounds.width - 150
        self.balanceLabelWidth.constant = maximumWidth
        
        // Calculate font size.
        let text = dimmed + filled
        let fullSize:CGFloat = 40
        let fullFont = UIFont(name: "Gilroy-Bold", size: fullSize) ?? .boldSystemFont(ofSize: fullSize)
        let fullWidth = (text as NSString).size(withAttributes: [.font: fullFont]).width
        let scale = fullWidth > 0 ? min(1, maximumWidth / fullWidth) : 1
        let pointSize = max(16, (fullSize * scale).rounded(.down))
        
        // Create the attributed text.
        let font = UIFont(name: "Gilroy-Bold", size: pointSize) ?? .boldSystemFont(ofSize: pointSize)
        let balance = NSMutableAttributedString(string: text, attributes: [.font: font, .foregroundColor: Colors.getColor("blackorwhite")])
        
        // Add the dimmed color.
        let dimmedColor = CacheManager.darkModeIsOn() ? UIColor(red: 170/255, green: 190/255, blue: 217/255, alpha: 1) : UIColor(red: 201/255, green: 154/255, blue: 0, alpha: 1)
        balance.addAttribute(.foregroundColor, value: dimmedColor, range: NSRange(location: 0, length: (dimmed as NSString).length))
        
        // Set the text.
        self.balanceLabel.adjustsFontSizeToFitWidth = true
        self.balanceLabel.minimumScaleFactor = 16.0 / pointSize
        self.balanceLabel.attributedText = balance
        
        // Hug the text vertically.
        self.balanceLabel.setContentHuggingPriority(.required, for: .vertical)
        self.bitcoinSign.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        
        // Make label and bitcoin sign visible.
        self.bitcoinSign.alpha = isWholeBitcoin ? 1 : (CacheManager.darkModeIsOn() ? 0.47 : 0.18)
        
        self.updateConversion()
    }
    
    func updateConversion() {
        
        // Set, cache, and show conversion label.
        let cachedBtcBalance = (CacheManager.cachedSatsBalance ?? "0").toNumber().inBTC()
        let conversionLabelText = self.updateConversionLabel(btcValue: cachedBtcBalance)
        CacheManager.cachedConversion = conversionLabelText
    }
    
    func updateConversionLabel(btcValue:CGFloat) -> String {
        
        // Use preferred currency.
        let bitcoinValue = BitcoinManager.shared.bittrWallet.getCorrectBitcoinValue()
        
        // Converted balance string.
        let balanceValue = String(Int((btcValue*bitcoinValue.currentValue).rounded())).addSpaces()
        
        // Set conversion label.
        self.conversionLabel.text = bitcoinValue.chosenCurrency + " " + balanceValue
        
        return self.conversionLabel.text ?? ""
    }
    
    func calculateProfit() {
        
        // Variables.
        var accumulatedProfit = 0
        var accumulatedInvestments = 0
        var accumulatedCurrentValue = 0
        
        // Get preferred currency.
        let bitcoinValue = BitcoinManager.shared.bittrWallet.getCorrectBitcoinValue()
        
        for eachTransaction in self.homeVC!.visibleTransactions where eachTransaction.isBittr {
            let transactionValue = eachTransaction.received.inBTC()
            var correctConversion = bitcoinValue.currentValue

            let transactionCurrency = eachTransaction.currency == "EUR" ? "€" : "CHF"
            if transactionCurrency != bitcoinValue.chosenCurrency {
                correctConversion = transactionCurrency == "€" ? (BitcoinManager.shared.bittrWallet.valueInEUR ?? 0) : (BitcoinManager.shared.bittrWallet.valueInCHF ?? 0)
            }

            var transactionProfit = (transactionValue*correctConversion) - eachTransaction.fiatNetAmount
            var transactionInvestment = eachTransaction.fiatNetAmount

            if transactionCurrency != bitcoinValue.chosenCurrency {
                transactionProfit = (transactionProfit/correctConversion)*bitcoinValue.currentValue
                transactionInvestment = (eachTransaction.fiatNetAmount/correctConversion)*bitcoinValue.currentValue
            }

            accumulatedProfit += Int(transactionProfit.rounded())
            accumulatedInvestments += Int(transactionInvestment.rounded())
            accumulatedCurrentValue += Int((transactionValue*bitcoinValue.currentValue).rounded())
        }

        self.showProfitLabel(currencySymbol: bitcoinValue.chosenCurrency, accumulatedProfit: accumulatedProfit, accumulatedInvestments: accumulatedInvestments, accumulatedCurrentValue: accumulatedCurrentValue)
    }
    
    
    func showProfitLabel(currencySymbol:String, accumulatedProfit:Int, accumulatedInvestments:Int, accumulatedCurrentValue:Int) {
        
        self.profitLabel.text = (accumulatedInvestments == 0) ? "0 %" : "\(Int(((CGFloat(accumulatedProfit)/CGFloat(accumulatedInvestments))*100).rounded())) %".replacingOccurrences(of: "-", with: "")
        
        if accumulatedProfit < 0 {
            // Loss
            self.profitLabel.textColor = Colors.getColor("losstext")
            self.profitView.backgroundColor = Colors.getColor("lossbackground0.8")
            self.profitArrow.tintColor = Colors.getColor("losstext")
            self.profitArrow.image = UIImage(systemName: "arrow.down")
        } else {
            // Profit
            self.profitLabel.textColor = Colors.getColor("profittext")
            self.profitView.backgroundColor = Colors.getColor("profitbackground0.8")
            self.profitArrow.tintColor = Colors.getColor("profittext")
            self.profitArrow.image = UIImage(systemName: "arrow.up")
        }
        
        self.homeVC!.calculatedProfit = accumulatedProfit
        self.homeVC!.calculatedInvestments = accumulatedInvestments
        self.homeVC!.calculatedCurrentValue = accumulatedCurrentValue
    }
}
