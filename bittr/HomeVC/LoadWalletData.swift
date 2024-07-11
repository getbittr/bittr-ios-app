//
//  LoadWalletData.swift
//  bittr
//
//  Created by Tom Melters on 08/02/2024.
//

import UIKit
import BitcoinDevKit
import LDKNode
import LDKNodeFFI
import Sentry

extension HomeViewController {

    @objc func loadWalletData(notification:NSNotification) {
        
        if let userInfo = notification.userInfo as [AnyHashable:Any]? {
            
            // Set current blockchain height.
            if let actualCurrentHeight = userInfo["currentheight"] as? Int {
                self.currentHeight = actualCurrentHeight
            }
            
            // Set Lightning channels.
            if let actualLightningChannels = userInfo["channels"] as? [ChannelDetails] {
                for eachChannel in actualLightningChannels {
                    self.btclnBalance += CGFloat(eachChannel.outboundCapacityMsat / 1000) + CGFloat(eachChannel.unspendablePunishmentReserve ?? 0)
                    self.channels = actualLightningChannels
                }
                
                // Users can currently only have one channel, their channel with Bittr. So this count is always 0 or 1.
                if actualLightningChannels.count == 1 {
                    // Set Bittr Channel.
                    let thisChannel = Channel()
                    thisChannel.id = actualLightningChannels[0].channelId
                    thisChannel.received = Int(actualLightningChannels[0].outboundCapacityMsat)/1000
                    thisChannel.size = Int(actualLightningChannels[0].channelValueSats)
                    thisChannel.punishmentReserve = Int(actualLightningChannels[0].unspendablePunishmentReserve ?? 0)
                    thisChannel.sendableMinimum = Int(actualLightningChannels[0].nextOutboundHtlcMinimumMsat)/1000
                    thisChannel.receivableMaximum = Int(actualLightningChannels[0].inboundHtlcMaximumMsat ?? 0)/1000
                    
                    self.bittrChannel = thisChannel
                    if let actualCoreVC = self.coreVC {
                        actualCoreVC.bittrChannel = thisChannel
                    }
                }
            }
            
            // Set onchain balance.
            if let actualBdkBalance = userInfo["bdkbalance"] as? Int {
                self.bdkBalance = CGFloat(actualBdkBalance)
            }
            
            // Set transactions.
            if let receivedTransactions = userInfo["transactions"] as? [TransactionDetails] {
                print("Received: \(receivedTransactions.count)")
                
                self.newTransactions.removeAll()
                
                // Add cached Lightning payments.
                let cachedLightningTransactions = CacheManager.getLightningTransactions()
                if let actualCachedLightningTransactions = cachedLightningTransactions {
                    self.newTransactions += actualCachedLightningTransactions
                    for eachTransaction in actualCachedLightningTransactions {
                        self.cachedLightningIds += [eachTransaction.id]
                    }
                }
                
                var txIds = [String]()
                for eachTransaction in receivedTransactions {
                    txIds += [eachTransaction.txid]
                }
                if let receivedPayments = userInfo["payments"] as? [PaymentDetails] {
                    for eachPayment in receivedPayments {
                        if eachPayment.id != nil {
                            if !self.cachedLightningIds.contains(eachPayment.id) {
                                txIds += [eachPayment.id ?? "Lightning transaction"]
                            }
                        }
                    }
                }
                if let cachedFundingTxo = CacheManager.getTxoID() {
                    txIds += [cachedFundingTxo]
                }
                
                Task {
                    // Check whether transactions were Bittr purchases.
                    await fetchTransactionData(txIds:txIds)
                    
                    DispatchQueue.main.async {
                        
                        // Create onchain transaction entities.
                        for eachTransaction in receivedTransactions {
                            
                            let thisTransaction = Transaction()
                            thisTransaction.id = eachTransaction.txid
                            thisTransaction.note = CacheManager.getTransactionNote(txid: eachTransaction.txid)
                            thisTransaction.fee = Int(eachTransaction.fee!)
                            thisTransaction.received = Int(eachTransaction.received)
                            thisTransaction.sent = Int(eachTransaction.sent)
                            thisTransaction.isLightning = false
                            if let confirmationTime = eachTransaction.confirmationTime {
                                thisTransaction.height = Int(confirmationTime.height)
                                thisTransaction.timestamp = Int(confirmationTime.timestamp)
                                if let actualCurrentHeight = self.currentHeight {
                                    thisTransaction.confirmations = actualCurrentHeight - thisTransaction.height
                                }
                            } else {
                                // Handle the case where confirmationTime is nil.
                                // For example, set a default value or leave it unassigned.
                                let defaultValue = 0
                                thisTransaction.height = defaultValue // Replace defaultValue with an appropriate value
                                thisTransaction.confirmations = 0
                                let currentTimestamp = Int(Date().timeIntervalSince1970)
                                thisTransaction.timestamp = currentTimestamp // Replace defaultValue with an appropriate value
                            }
                            if (self.bittrTransactions.allKeys as! [String]).contains(thisTransaction.id) {
                                thisTransaction.isBittr = true
                                thisTransaction.purchaseAmount = Int(CGFloat(truncating: NumberFormatter().number(from: ((self.bittrTransactions[thisTransaction.id] as! [String:Any])["amount"] as! String).replacingOccurrences(of: ".", with: Locale.current.decimalSeparator!).replacingOccurrences(of: ",", with: Locale.current.decimalSeparator!))!))
                                thisTransaction.currency = (self.bittrTransactions[thisTransaction.id] as! [String:Any])["currency"] as! String
                            }
                            
                            self.newTransactions += [thisTransaction]
                        }
                        
                        // Create lightning transaction entities.
                        if let receivedPayments = userInfo["payments"] as? [PaymentDetails] {
                            
                            for eachPayment in receivedPayments {
                                if !self.cachedLightningIds.contains(eachPayment.id ?? "Lightning transaction") {
                                    let thisTransaction = Transaction()
                                    if eachPayment.direction == .inbound {
                                        thisTransaction.received = Int(eachPayment.amountMsat ?? 0)/1000
                                    } else {
                                        thisTransaction.sent = Int(eachPayment.amountMsat ?? 0)/1000
                                    }
                                    thisTransaction.isLightning = true
                                    thisTransaction.timestamp = CacheManager.getInvoiceTimestamp(hash: eachPayment.id)
                                    thisTransaction.lnDescription = CacheManager.getInvoiceDescription(hash: eachPayment.id)
                                    thisTransaction.id = eachPayment.id ?? "Lightning transaction"
                                    thisTransaction.note = CacheManager.getTransactionNote(txid: thisTransaction.id)
                                    if let actualChannels = self.channels {
                                        thisTransaction.channelId = actualChannels[0].channelId
                                    }
                                    
                                    if (self.bittrTransactions.allKeys as! [String]).contains(thisTransaction.id) {
                                        thisTransaction.isBittr = true
                                        thisTransaction.purchaseAmount = Int(CGFloat(truncating: NumberFormatter().number(from: ((self.bittrTransactions[thisTransaction.id] as! [String:Any])["amount"] as! String).replacingOccurrences(of: ".", with: Locale.current.decimalSeparator!).replacingOccurrences(of: ",", with: Locale.current.decimalSeparator!))!))
                                        thisTransaction.currency = (self.bittrTransactions[thisTransaction.id] as! [String:Any])["currency"] as! String
                                    }
                                    
                                    if eachPayment.status == .succeeded {
                                        self.newTransactions += [thisTransaction]
                                        CacheManager.storeLightningTransaction(thisTransaction: thisTransaction)
                                    }
                                }
                            }
                        }
                        
                        // Sort all transactions by date/time.
                        self.newTransactions.sort { transaction1, transaction2 in
                            transaction1.timestamp > transaction2.timestamp
                        }
                        
                        // Store transactions in cache.
                        CacheManager.updateCachedData(data: self.newTransactions, key: "transactions")
                        
                        // Start balance calculation.
                        self.setTotalSats()
                    }
                }
            } else {
                // Start balance calculation.
                self.setTotalSats()
            }
        }
    }
    
    
    func fetchTransactionData(txIds:[String]) async -> Bool {
        
        // Check if transactions were Bittr purchases with the Bittr API.
        
        // Get this user's unique Bittr codes.
        var depositCodes = [String]()
        for eachIbanEntity in self.client.ibanEntities {
            if eachIbanEntity.yourUniqueCode != "" {
                depositCodes += [eachIbanEntity.yourUniqueCode]
            }
        }
        
        // Add previously cached transactions to Bittr transactions array.
        var cachedBittrTransactionIDs = [String]()
        self.bittrTransactions = NSMutableDictionary()
        for eachTransaction in self.lastCachedTransactions {
            if eachTransaction.isBittr == true {
                self.bittrTransactions.setValue(["amount":"\(eachTransaction.purchaseAmount)", "currency":eachTransaction.currency], forKey: eachTransaction.id)
                cachedBittrTransactionIDs += [eachTransaction.id]
            }
        }
        
        // Collect the txIDs that have not been checked against the Bittr API before.
        var newTxIds = [String]()
        for eachTxId in txIds {
            if !cachedBittrTransactionIDs.contains(eachTxId) {
                if !self.cachedLightningIds.contains(eachTxId) {
                    if let previouslySentToBittr = CacheManager.getSentToBittr() {
                        if !previouslySentToBittr.contains(eachTxId) {
                            newTxIds += [eachTxId]
                        }
                    } else {
                        newTxIds += [eachTxId]
                    }
                }
            } else if eachTxId == CacheManager.getTxoID() ?? "" {
                if !self.cachedLightningIds.contains(eachTxId) {
                    newTxIds += [eachTxId]
                }
            }
        }
        
        print("TxIds being sent to Bittr: \(newTxIds.count)")
        
        if newTxIds.count == 0 {
            // No new txIDs need to be checked with the Bittr API.
            return false
        } else {
            // Some new txIDs need to be checked with the Bittr API.
            do {
                let bittrApiTransactions = try await BittrService.shared.fetchBittrTransactions(txIds: newTxIds, depositCodes: depositCodes)
                print("Bittr transactions: \(bittrApiTransactions.count)")
                
                CacheManager.updateSentToBittr(txids: newTxIds)
                
                if bittrApiTransactions.count == 0 {
                    // There are no Bittr transactions.
                    return false
                } else {
                    // There are Bittr transactions.
                    
                    for eachTransaction in bittrApiTransactions {
                        
                        if eachTransaction.txId == CacheManager.getTxoID() ?? "" {
                            // This is the funding Txo.
                            let formatter = DateFormatter()
                            formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS"
                            let transactionDate = formatter.date(from:eachTransaction.datetime)!
                            let transactionTimestamp = Int(transactionDate.timeIntervalSince1970)
                            
                            let thisTransaction = Transaction()
                            thisTransaction.isBittr = true
                            thisTransaction.isLightning = true
                            thisTransaction.purchaseAmount = Int(CGFloat(truncating: NumberFormatter().number(from: (eachTransaction.purchaseAmount).replacingOccurrences(of: ".", with: Locale.current.decimalSeparator!).replacingOccurrences(of: ",", with: Locale.current.decimalSeparator!))!))
                            thisTransaction.currency = eachTransaction.currency
                            thisTransaction.id = eachTransaction.txId
                            thisTransaction.sent = 0
                            thisTransaction.received = Int(CGFloat(truncating: NumberFormatter().number(from: (eachTransaction.bitcoinAmount).replacingOccurrences(of: ".", with: Locale.current.decimalSeparator!).replacingOccurrences(of: ",", with: Locale.current.decimalSeparator!))!)*100000000)
                            thisTransaction.timestamp = transactionTimestamp
                            thisTransaction.lnDescription = CacheManager.getInvoiceDescription(hash: eachTransaction.txId)
                            if let actualChannels = self.channels {
                                thisTransaction.channelId = actualChannels[0].channelId
                            }
                            thisTransaction.isFundingTransaction = true
                            self.newTransactions += [thisTransaction]
                            CacheManager.storeLightningTransaction(thisTransaction: thisTransaction)
                        } else {
                            self.bittrTransactions.setValue(["amount":eachTransaction.purchaseAmount, "currency":eachTransaction.currency], forKey: eachTransaction.txId)
                        }
                    }
                    
                    return true
                }
            } catch {
                print("Bittr error: \(error.localizedDescription)")
                return false
            }
        }
    }
    
    
    func setTotalSats() {
        
        // Calculate total balance
        self.btcBalance = self.bdkBalance
        self.totalBalanceSats = self.btcBalance + self.btclnBalance
        let totalBalanceSatsString = "\(Int(self.totalBalanceSats))"
        self.balanceWasFetched = true
        
        // Create balance representation with bold satoshis.
        var zeros = "0.00 000 00"
        var numbers = "\(self.btcBalance)"
        var bitcoinSignAlpha = 0.18
        
        switch totalBalanceSatsString.count {
        case 1:
            zeros = "0.00 000 00"
            numbers = totalBalanceSatsString
        case 2:
            zeros = "0.00 000 0"
            numbers = totalBalanceSatsString
        case 3:
            zeros = "0.00 000 "
            numbers = totalBalanceSatsString
        case 4:
            zeros = "0.00 00"
            numbers = totalBalanceSatsString[0] + " " + totalBalanceSatsString[1..<4]
        case 5:
            zeros = "0.00 0"
            numbers = totalBalanceSatsString[0..<2] + " " + totalBalanceSatsString[2..<5]
        case 6:
            zeros = "0.00 "
            numbers = totalBalanceSatsString[0..<3] + " " + totalBalanceSatsString[3..<6]
        case 7:
            zeros = "0.0"
            numbers = totalBalanceSatsString[0] + " " + totalBalanceSatsString[1..<4] + " " + totalBalanceSatsString[4..<7]
        case 8:
            zeros = "0."
            numbers = totalBalanceSatsString[0..<2] + " " + totalBalanceSatsString[2..<5] + " " + totalBalanceSatsString[5..<8]
        default:
            zeros = ""
            numbers = "\(totalBalanceSats/100000000)"
            bitcoinSignAlpha = 1
        }
        
        // Set text to invisible label to calculate font size for HTML text.
        balanceLabelInvisible.text = "B " + zeros + numbers + " sats"
        let font = balanceLabelInvisible.adjustedFont()
        self.satsLabel.font = font
        let adjustedSize = Int(font.pointSize)
        
        // Set HTML balance text.
        balanceText = "<center><span style=\"font-family: \'Gilroy-Bold\', \'-apple-system\'; font-size: \(adjustedSize); color: rgb(201, 154, 0); line-height: 0.5\">\(zeros)</span><span style=\"font-family: \'Gilroy-Bold\', \'-apple-system\'; font-size: \(adjustedSize); color: rgb(0, 0, 0); line-height: 0.5\">\(numbers)</span></center>"
        
        // Store HTML balance text to cache.
        CacheManager.updateCachedData(data: balanceText, key: "balance")
        
        if let htmlData = balanceText.data(using: .unicode) {
            do {
                let attributedText = try NSAttributedString(data: htmlData, options: [NSAttributedString.DocumentReadingOptionKey.documentType : NSAttributedString.DocumentType.html], documentAttributes: nil)
                balanceLabel.attributedText = attributedText
                balanceLabel.alpha = 1
                bitcoinSign.alpha = bitcoinSignAlpha
                
                // Don't show "sats" label if user has 1 or more bitcoin.
                if bitcoinSignAlpha == 1 {
                    satsLabel.alpha = 0
                } else {
                    satsLabel.alpha = 1
                }
                
                // Store satoshis balance string to cache.
                CacheManager.updateCachedData(data: totalBalanceSatsString, key: "satsbalance")
                
                // Convert bitcoin balance to EUR / CHF.
                self.setConversion(btcValue: CGFloat(truncating: NumberFormatter().number(from: totalBalanceSatsString)!)/100000000, cachedData: false)
                
            } catch let e as NSError {
                print("Couldn't fetch text: \(e.localizedDescription)")
            }
        }
    }
    
    
    func setConversion(btcValue:CGFloat, cachedData:Bool) {
        
        if self.didFetchConversion == true || self.couldNotFetchConversion == true {
            // Conversion rate was already fetched.
            print("Did start currency conversion with cached conversion rate.")
            
            let conversionLabelText = self.updateConversionLabel(btcValue: btcValue)
            
            // Store conversion text to cache.
            CacheManager.updateCachedData(data: conversionLabelText, key: "conversion")
            
            // Show label.
            self.balanceSpinner.stopAnimating()
            self.conversionLabel.alpha = 1
            
            if cachedData == false {
                self.setTransactions = self.newTransactions
            }
            
            self.updateTableAfterConversion()
            
            self.calculateProfit(cachedData: cachedData)
        } else {
            // Conversion rate hasn't yet been fetched.
            print("Did start currency conversion.")
            
            if let actualCoreVC = self.coreVC {
                actualCoreVC.startSync(type: "conversion")
            }
            
            // TODO: Public?
            var envUrl = "https://getbittr.com/api/price/btc"
            if UserDefaults.standard.value(forKey: "envkey") as? Int == 0 {
                envUrl = "https://staging.getbittr.com/api/price/btc"
            }
            
            // Get currency conversion rate from Bittr API.
            var request = URLRequest(url: URL(string: envUrl)!,timeoutInterval: Double.infinity)
            
            let task = URLSession.shared.dataTask(with: request) { data, response, error in
                guard let data = data else {
                    print("Conversion error:" + String(describing: error))
                    
                    DispatchQueue.main.async {
                        let alert = UIAlertController(title: "Oops!", message: "We're experiencing an issue fetching the latest conversion rates. Temporarily, our calculations - if available - won't reflect bitcoin's current value.", preferredStyle: .alert)
                        alert.addAction(UIAlertAction(title: "Okay", style: .cancel, handler: nil))
                        self.present(alert, animated: true)
                        
                        self.couldNotFetchConversion = true
                        self.setConversion(btcValue: btcValue, cachedData: cachedData)
                        if let actualError = error {
                            SentrySDK.capture(error: actualError)
                        }
                    }
                    
                    return
                }
                
                // Data has been received.
                var dataDictionary:NSDictionary?
                if let receivedData = String(data: data, encoding: .utf8)?.data(using: String.Encoding.utf8) {
                    do {
                        dataDictionary = try JSONSerialization.jsonObject(with: receivedData, options: []) as? NSDictionary
                        if let actualDataDict = dataDictionary {
                            if var actualEurValue = actualDataDict["btc_eur"] as? String, var actualChfValue = actualDataDict["btc_chf"] as? String {
                                
                                if actualEurValue.contains("."), Locale.current.decimalSeparator == "," {
                                    actualEurValue = actualEurValue.replacingOccurrences(of: ".", with: ",")
                                    actualChfValue = actualChfValue.replacingOccurrences(of: ".", with: ",")
                                } else if actualEurValue.contains(","), Locale.current.decimalSeparator == "." {
                                    actualEurValue = actualEurValue.replacingOccurrences(of: ",", with: ".")
                                    actualChfValue = actualChfValue.replacingOccurrences(of: ",", with: ".")
                                }
                                
                                // Set updated conversion rates for EUR and CHF.
                                self.eurValue = CGFloat(truncating: NumberFormatter().number(from: actualEurValue)!)
                                self.chfValue = CGFloat(truncating: NumberFormatter().number(from: actualChfValue)!)
                                
                                // Store updated conversion rates in cache.
                                CacheManager.updateCachedData(data: self.eurValue, key: "eurvalue")
                                CacheManager.updateCachedData(data: self.chfValue, key: "chfvalue")
                                
                                // Share updated conversion rates with the Core View Controller.
                                if let actualCoreVC = self.coreVC {
                                    actualCoreVC.eurValue = self.eurValue
                                    actualCoreVC.chfValue = self.chfValue
                                }
                                
                                self.didFetchConversion = true
                                
                                DispatchQueue.main.async {
                                    
                                    let conversionLabelText = self.updateConversionLabel(btcValue: btcValue)
                                    CacheManager.updateCachedData(data: conversionLabelText, key: "conversion")
                                    
                                    // Show conversion label.
                                    self.balanceSpinner.stopAnimating()
                                    self.conversionLabel.alpha = 1
                                    
                                    if cachedData == false {
                                        self.setTransactions = self.newTransactions
                                    }
                                    
                                    self.updateTableAfterConversion()
                                    
                                    if let actualCoreVC = self.coreVC {
                                        actualCoreVC.completeSync(type: "conversion")
                                    }
                                    
                                    self.calculateProfit(cachedData: cachedData)
                                }
                            }
                        }
                    } catch let error as NSError {
                        print("Conversion error:" + error.localizedDescription)
                        
                        DispatchQueue.main.async {
                            let alert = UIAlertController(title: "Oops!", message: "We're experiencing an issue fetching the latest conversion rates. Temporarily, our calculations - if available - won't reflect bitcoin's current value.", preferredStyle: .alert)
                            alert.addAction(UIAlertAction(title: "Okay", style: .cancel, handler: nil))
                            self.present(alert, animated: true)
                            
                            self.couldNotFetchConversion = true
                            self.setConversion(btcValue: btcValue, cachedData: cachedData)
                            SentrySDK.capture(error: error)
                        }
                    }
                }
            }
            task.resume()
        }
    }
    
    func updateConversionLabel(btcValue:CGFloat) -> String {
        
        // Use preferred currency.
        var correctValue:CGFloat = self.eurValue
        var currencySymbol = "€"
        if UserDefaults.standard.value(forKey: "currency") as? String == "CHF" {
            correctValue = self.chfValue
            currencySymbol = "CHF"
        }
        
        // Converted balance string.
        let balanceValue = addSpacesToString(balanceValue: String(Int((btcValue*correctValue).rounded())))
        
        // Set conversion label.
        self.conversionLabel.text = currencySymbol + " " + balanceValue
        
        return self.conversionLabel.text ?? ""
    }
    
    func updateTableAfterConversion() {
        
        self.homeTableView.reloadData()
        self.homeTableView.alpha = 1
        self.tableSpinner.stopAnimating()
        
        if self.setTransactions.count == 0 {
            let noTransactionsHTML = "<center><span style=\"font-family: \'Gilroy-Regular\', \'-apple-system\'; font-size: 16; color: rgb(177, 177, 177); line-height: 1.2\">There are no transactions. Tap </span><span style=\"font-family: \'Gilroy-Bold\', \'-apple-system\'; font-size: 16; color: rgb(177, 177, 177); line-height: 1.2\">Buy</span><span style=\"font-family: \'Gilroy-Regular\', \'-apple-system\'; font-size: 16; color: rgb(177, 177, 177); line-height: 1.2\"> to get your first bitcoin.</span></center>"
            
            if let htmlData = noTransactionsHTML.data(using: .unicode) {
                do {
                    let attributedText = try NSAttributedString(data: htmlData, options: [NSAttributedString.DocumentReadingOptionKey.documentType : NSAttributedString.DocumentType.html], documentAttributes: nil)
                    self.noTransactionsLabel.attributedText = attributedText
                    self.noTransactionsLabel.alpha = 1
                } catch let e as NSError {
                    print("Couldn't fetch text: \(e.localizedDescription)")
                }
            }
        } else {
            self.noTransactionsLabel.alpha = 0
        }
    }
    
    func calculateProfit(cachedData:Bool) {
        
        print("Did start calculating profit.")
        
        self.didStartReset = false
        
        // Hide profit label while calculating.
        self.bittrProfitLabel.alpha = 0
        self.bittrProfitSpinner.startAnimating()
        
        // Variables.
        let bittrTransactionsCount = self.bittrTransactions.count
        var handledTransactions = 0
        var accumulatedProfit = 0
        var accumulatedInvestments = 0
        var accumulatedCurrentValue = 0
        
        // Get preferred currency.
        var correctValue:CGFloat = self.eurValue
        var currencySymbol = "€"
        if UserDefaults.standard.value(forKey: "currency") as? String == "CHF" {
            correctValue = self.chfValue
            currencySymbol = "CHF"
        }
        
        if self.setTransactions.count == 0 || bittrTransactionsCount == 0 {
            // There are no transactions.
            self.bittrProfitLabel.text = "\(currencySymbol) \(accumulatedProfit)"
            self.bittrProfitLabel.alpha = 1
            self.bittrProfitSpinner.stopAnimating()
            
            self.calculatedProfit = accumulatedProfit
            self.calculatedInvestments = accumulatedInvestments
            self.calculatedCurrentValue = accumulatedCurrentValue
        } else {
            for eachTransaction in self.setTransactions {
                
                if eachTransaction.isBittr == true {
                    
                    handledTransactions += 1
                    let transactionValue = CGFloat(eachTransaction.received)/100000000
                    let transactionProfit = Int((transactionValue*correctValue).rounded())-eachTransaction.purchaseAmount
                    
                    accumulatedProfit += transactionProfit
                    accumulatedInvestments += eachTransaction.purchaseAmount
                    accumulatedCurrentValue += Int((transactionValue*correctValue).rounded())
                    
                    if bittrTransactionsCount == handledTransactions {
                        // We're done counting.
                        
                        self.bittrProfitLabel.text = "\(currencySymbol) \(accumulatedProfit)"
                        self.bittrProfitLabel.alpha = 1
                        self.bittrProfitSpinner.stopAnimating()
                        
                        self.calculatedProfit = accumulatedProfit
                        self.calculatedInvestments = accumulatedInvestments
                        self.calculatedCurrentValue = accumulatedCurrentValue
                    }
                } else {
                    
                    if bittrTransactionsCount == handledTransactions {
                        
                        self.bittrProfitLabel.text = "\(currencySymbol) \(accumulatedProfit)"
                        self.bittrProfitLabel.alpha = 1
                        self.bittrProfitSpinner.stopAnimating()
                        
                        self.calculatedProfit = accumulatedProfit
                        self.calculatedInvestments = accumulatedInvestments
                        self.calculatedCurrentValue = accumulatedCurrentValue
                    }
                }
            }
        }
        
        if cachedData == false {
            self.headerLabel.text = "your wallet"
            self.headerSpinner.stopAnimating()
            
            if self.couldNotFetchConversion == true {
                self.headerProblemImage.alpha = 1
            } else {
                self.headerLabelLeading.constant = -10
            }
            
            if let actualCoreVC = self.coreVC {
                actualCoreVC.walletHasSynced = true
                actualCoreVC.completeSync(type: "final")
            }
        }
        
        if cachedData == false {
            if let actualCoreVC = self.coreVC {
                if actualCoreVC.needsToHandleNotification == true, let actualNotification = actualCoreVC.lightningNotification {
                    actualCoreVC.handlePaymentNotification(notification: actualNotification)
                }
            }
            self.fetchAndPrintPeers()
        } else {
            print("Did calculate cached profits.")
        }
    }

}

extension UILabel{
    func adjustedFont()->UIFont {
        guard let txt = text else {
            return self.font
        }
        let attributes: [NSAttributedString.Key: Any] = [.font: self.font]
        let attributedString = NSAttributedString(string: txt, attributes: attributes)
        let drawingContext = NSStringDrawingContext()
        drawingContext.minimumScaleFactor = self.minimumScaleFactor
        attributedString.boundingRect(with: bounds.size,
                                      options: [.usesLineFragmentOrigin,.usesFontLeading],
                                      context: drawingContext)

        let fontSize = font.pointSize * drawingContext.actualScaleFactor
        return font.withSize(CGFloat(floor(Double(fontSize))))
    }
}
