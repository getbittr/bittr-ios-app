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
        
        // Words and colors.
        self.setWords()
        self.changeColors()
        
        // Balance and conversion.
        self.updateBalanceLabel()
        
        // Profit.
        self.calculateProfit()
        
        // Bitcoin value graph.
        self.loadGraph()
        
        // Stop sync status spinner.
        if homeVC.coreVC!.walletHasSynced {
            self.showLabels()
        } else {
            self.headerSpinner.startAnimating()
        }
        
        // Check noTransactionsLabel.
        self.noTransactionsLabel.alpha = (!homeVC.didStartReset && homeVC.visibleTransactions.count == 0) ? 1 : 0
    }
    
    func loadGraph() {
        guard let homeVC = self.homeVC else { return }
        
        self.conversionGraph.horizontalInset = 27
        self.conversionGraph.topInset = 16
        self.conversionGraph.bottomInset = 21
        self.conversionGraph.lineWidth = 4
        self.conversionGraph.pointRadius = 0
        self.conversionGraph.isInteractive = false
        self.conversionGraph.lineColor = Colors.returnColor(.white, 1)
        
        // Show whatever has already been fetched.
        self.conversionGraph.points = homeVC.graphPoints ?? []
        
        guard homeVC.didFetchConversion || homeVC.couldNotFetchConversion else { return }
        guard homeVC.graphPoints == nil, !homeVC.isLoadingGraph else { return }
        // Back off after a failure rather than trying again on the next reload.
        if let failedAt = homeVC.graphLoadFailedAt, Date().timeIntervalSince(failedAt) < 60 { return }
        
        homeVC.isLoadingGraph = true
        
        Task { [weak self, weak homeVC] in
            defer { homeVC?.isLoadingGraph = false }
            guard let snapshot = try? await PriceHistory.load(cache: homeVC), let points = snapshot.series[.week] else {
                homeVC?.graphLoadFailedAt = Date()
                return
            }
            homeVC?.graphLoadFailedAt = nil
            homeVC?.graphPoints = points
            self?.conversionGraph.points = points
            self?.updateGraphProfit()
        }
    }
    
    func updateGraphProfit() {
        guard let homeVC = self.homeVC, !homeVC.didStartReset, let points = homeVC.graphPoints, let firstPrice = points.first?.price, let lastPrice = points.last?.price, firstPrice > 0 else {
            self.conversionProfitView.alpha = 0
            return
        }
        
        let profit = (lastPrice - firstPrice)/firstPrice * 100
        let profitPercentage = "\(Int(profit)) %"
        self.conversionProfitLabel.text = profitPercentage
        
        if profitPercentage.contains("-") {
            // Loss
            self.conversionProfitLabel.textColor = Colors.getColor("losstext")
            self.conversionProfitView.backgroundColor = Colors.getColor("lossbackground0.8")
            self.conversionProfitArrow.tintColor = Colors.getColor("losstext")
            self.conversionProfitArrow.image = UIImage(systemName: "arrow.down")
        } else {
            // Profit
            self.conversionProfitLabel.textColor = Colors.getColor("profittext")
            self.conversionProfitView.backgroundColor = Colors.getColor("profitbackground0.8")
            self.conversionProfitArrow.tintColor = Colors.getColor("profittext")
            self.conversionProfitArrow.image = UIImage(systemName: "arrow.up")
        }
        
        self.conversionProfitView.alpha = 1
    }
    
    func showLabels() {
        self.profitView.alpha = 1
        self.balanceView.alpha = 1
        self.conversionLabel.alpha = 1
        self.headerSpinner.stopAnimating()
        
        guard let homeVC = self.homeVC else { return }
        self.headerProblemImage.alpha = homeVC.couldNotFetchConversion ? 1 : 0
    }
    
    func hideLabels() {
        
        self.noTransactionsLabel.alpha = 0
        self.profitView.alpha = 0
        self.balanceView.alpha = 0
        self.conversionLabel.alpha = 0
        self.conversionProfitView.alpha = 0
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
