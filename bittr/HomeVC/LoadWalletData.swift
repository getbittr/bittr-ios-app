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

extension HomeViewController {

    @objc func loadWalletData(notification:NSNotification) {
        
        // Step 10.
        if let userInfo = notification.userInfo as [AnyHashable:Any]? {
            
            if let actualCurrentHeight = userInfo["currentheight"] as? Int {
                self.currentHeight = actualCurrentHeight
            }
            
            if let actualLightningChannels = userInfo["channels"] as? [ChannelDetails] {
                for eachChannel in actualLightningChannels {
                    self.btclnBalance += CGFloat(eachChannel.outboundCapacityMsat / 1000)
                    self.channels = actualLightningChannels
                }
            }
            
            if let actualLightningNodeService = userInfo["lightningnodeservice"] as? LightningNodeService {
                self.lightningNodeService = actualLightningNodeService
            }
            
            if let actualBdkBalance = userInfo["bdkbalance"] as? Int {
                self.bdkBalance = CGFloat(actualBdkBalance)
            }
            
            if let receivedTransactions = userInfo["transactions"] as? [TransactionDetails] {
                print("Received: \(receivedTransactions.count)")
                
                //self.setTransactions.removeAll()
                self.newTransactions.removeAll()
                
                // TODO: Hide after testing.
                //CacheManager.deleteLightningTransactions()
                
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
                        if eachPayment.preimage != nil {
                            if !self.cachedLightningIds.contains(eachPayment.preimage!) {
                                txIds += [eachPayment.preimage ?? "Lightning transaction"]
                            }
                        }
                    }
                }
                if let cachedFundingTxo = CacheManager.getTxoID() {
                    txIds += [cachedFundingTxo]
                }
                
                Task {
                    await fetchTransactionData(txIds:txIds)
                    
                    DispatchQueue.main.async {
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
                        
                        if let receivedPayments = userInfo["payments"] as? [PaymentDetails] {
                            
                            for eachPayment in receivedPayments {
                                if !self.cachedLightningIds.contains(eachPayment.preimage ?? "Lightning transaction") {
                                    let thisTransaction = Transaction()
                                    if eachPayment.direction == .inbound {
                                        thisTransaction.received = Int(eachPayment.amountMsat ?? 0)/1000
                                    } else {
                                        thisTransaction.sent = Int(eachPayment.amountMsat ?? 0)/1000
                                    }
                                    thisTransaction.isLightning = true
                                    thisTransaction.timestamp = CacheManager.getInvoiceTimestamp(hash: eachPayment.hash)
                                    thisTransaction.lnDescription = CacheManager.getInvoiceDescription(hash: eachPayment.hash)
                                    thisTransaction.id = eachPayment.preimage ?? "Lightning transaction"
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
                        
                        self.newTransactions.sort { transaction1, transaction2 in
                            transaction1.timestamp > transaction2.timestamp
                        }
                        
                        CacheManager.updateCachedData(data: self.newTransactions, key: "transactions")
                        
                        // Step 11.
                        /*let bitcoinViewModel = BitcoinViewModel()
                        Task {
                            print("Will fetch onchain balance.")
                            await bitcoinViewModel.getTotalOnchainBalanceSats()
                        }*/
                        NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "settotalsats"), object: nil, userInfo: nil) as Notification)
                    }
                }
            } else {
                // Step 11.
                /*let bitcoinViewModel = BitcoinViewModel()
                Task {
                    print("Will fetch onchain balance.")
                    await bitcoinViewModel.getTotalOnchainBalanceSats()
                }*/
                NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "settotalsats"), object: nil, userInfo: nil) as Notification)
            }
        }
    }
    
    
    func fetchTransactionData(txIds:[String]) async -> Bool {
        
        var depositCodes = [String]()
        for eachIbanEntity in self.client.ibanEntities {
            if eachIbanEntity.yourUniqueCode != "" {
                depositCodes += [eachIbanEntity.yourUniqueCode]
            }
        }
        
        //depositCodes += ["5GCPDLWU5FVQ"]
        
        var cachedBittrTransactionIDs = [String]()
        self.bittrTransactions = NSMutableDictionary()
        for eachTransaction in self.lastCachedTransactions {
            if eachTransaction.isBittr == true {
                self.bittrTransactions.setValue(["amount":"\(eachTransaction.purchaseAmount)", "currency":eachTransaction.currency], forKey: eachTransaction.id)
                cachedBittrTransactionIDs += [eachTransaction.id]
            }
        }
        
        var newTxIds = [String]()
        for eachTxId in txIds {
            if !cachedBittrTransactionIDs.contains(eachTxId) {
                if !self.cachedLightningIds.contains(eachTxId) {
                    newTxIds += [eachTxId]
                }
            } else if eachTxId == CacheManager.getTxoID() ?? "" {
                if !self.cachedLightningIds.contains(eachTxId) {
                    newTxIds += [eachTxId]
                }
            }
        }
        
        print("TxIds being sent to Bittr: \(newTxIds.count)")
        
        do {
            let bittrApiTransactions = try await BittrService.shared.fetchBittrTransactions(txIds: newTxIds, depositCodes: depositCodes)
            print("Bittr transactions: \(bittrApiTransactions.count)")
            
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
                        //Int(CGFloat(truncating: NumberFormatter().number(from: (eachTransaction.purchaseAmount).replacingOccurrences(of: ".", with: Locale.current.decimalSeparator!).replacingOccurrences(of: ",", with: Locale.current.decimalSeparator!))!) / CGFloat(truncating: NumberFormatter().number(from: (eachTransaction.historicalExchangeRate).replacingOccurrences(of: ".", with: Locale.current.decimalSeparator!).replacingOccurrences(of: ",", with: Locale.current.decimalSeparator!))!) * 100000000)
                        thisTransaction.timestamp = transactionTimestamp
                        thisTransaction.lnDescription = CacheManager.getInvoiceDescription(hash: eachTransaction.txId)
                        if let actualChannels = self.channels {
                            thisTransaction.channelId = actualChannels[0].channelId
                        }
                        thisTransaction.isFundingTransaction = true
                        self.newTransactions += [thisTransaction]
                        CacheManager.storeLightningTransaction(thisTransaction: thisTransaction)
                        
                        //self.bittrTransactions.setValue(["amount":eachTransaction.purchaseAmount, "currency":eachTransaction.currency, "date":transactionTimestamp], forKey: eachTransaction.txId)
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
    
    
    @objc func setTotalSats(notification:NSNotification) {
        
        // Step 13.
        
        /*if let userInfo = notification.userInfo as [AnyHashable:Any]? {
            if let satsBalance = userInfo["balance"] as? String {*/
        self.btcBalance = self.bdkBalance
                var zeros = "0.00 000 00"
                var numbers = "\(self.btcBalance)"
                
                //self.btcBalance = CGFloat(truncating: NumberFormatter().number(from: satsBalance)!)
                self.balanceWasFetched = true
                
                /*if self.btcBalance == 0.0, self.btclnBalance == 0.0, self.bdkBalance != 0.0 {
                    self.btcBalance = self.bdkBalance
                }*/
                self.totalBalanceSats = self.btcBalance + self.btclnBalance
                let totalBalanceSatsString = "\(Int(self.totalBalanceSats))"
                
                var bitcoinSignAlpha = 0.22
                
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
                
                balanceText = "<center><span style=\"font-family: \'Syne-Regular\', \'-apple-system\'; font-size: 38; color: rgb(201, 154, 0); line-height: 0.5\">\(zeros)</span><span style=\"font-family: \'Syne-Regular\', \'-apple-system\'; font-size: 38; color: rgb(0, 0, 0); line-height: 0.5\">\(numbers)</span></center>"
                
                CacheManager.updateCachedData(data: balanceText, key: "balance")
                
                if let htmlData = balanceText.data(using: .unicode) {
                    do {
                        let attributedText = try NSAttributedString(data: htmlData, options: [NSAttributedString.DocumentReadingOptionKey.documentType : NSAttributedString.DocumentType.html], documentAttributes: nil)
                        balanceLabel.attributedText = attributedText
                        balanceLabel.alpha = 1
                        bitcoinSign.alpha = bitcoinSignAlpha
                        if bitcoinSignAlpha == 1 {
                            satsSign.alpha = 0
                            questionCircle.alpha = 0
                        } else {
                            satsSign.alpha = 1
                            questionCircle.alpha = 0.4
                        }
                        
                        // Step 14.
                        CacheManager.updateCachedData(data: totalBalanceSatsString, key: "satsbalance")
                        self.setConversion(btcValue: CGFloat(truncating: NumberFormatter().number(from: totalBalanceSatsString)!)/100000000, cachedData: false)
                        
                    } catch let e as NSError {
                        print("Couldn't fetch text: \(e.localizedDescription)")
                    }
                }
            //}
        //}
    }
    
    
    func setConversion(btcValue:CGFloat, cachedData:Bool) {
        
        // Step 15.
        
        if self.didFetchConversion == true {
            // Conversion rate was already fetched.
            print("Did start currency conversion with cached conversion rate.")
            
            var correctValue:CGFloat = self.eurValue
            var currencySymbol = "€"
            if UserDefaults.standard.value(forKey: "currency") as? String == "CHF" {
                correctValue = self.chfValue
                currencySymbol = "CHF"
            }
            
            var balanceValue = String(Int((btcValue*correctValue).rounded()))
            
            switch balanceValue.count {
            case 0..<4:
                balanceValue = String(Int((btcValue*correctValue).rounded()))
            case 4:
                balanceValue = balanceValue[0] + " " + balanceValue[1..<4]
            case 5:
                balanceValue = balanceValue[0..<2] + " " + balanceValue[2..<5]
            case 6:
                balanceValue = balanceValue[0..<3] + " " + balanceValue[3..<6]
            case 7:
                balanceValue = balanceValue[0] + " " + balanceValue[1..<4] + " " + balanceValue[4..<7]
            case 8:
                balanceValue = balanceValue[0..<2] + " " + balanceValue[2..<5] + " " + balanceValue[5..<8]
            case 9:
                balanceValue = balanceValue[0..<3] + " " + balanceValue[3..<6] + " " + balanceValue[6..<9]
            default:
                balanceValue = String(Int((btcValue*correctValue).rounded()))
            }
            
            self.conversionLabel.text = currencySymbol + " " + balanceValue
            CacheManager.updateCachedData(data: currencySymbol + " " + balanceValue, key: "conversion")
            self.balanceSpinner.stopAnimating()
            self.conversionLabel.alpha = 1
            
            if cachedData == false {
                self.setTransactions = self.newTransactions
            }
            
            self.homeTableView.reloadData()
            //self.homeTableView.isUserInteractionEnabled = true
            self.homeTableView.alpha = 1
            self.tableSpinner.stopAnimating()
            
            // Step 16.
            self.calculateProfit(cachedData: cachedData)
        } else {
            
            print("Did start currency conversion.")
            
            var request = URLRequest(url: URL(string: "https://staging.getbittr.com/api/price/btc")!,timeoutInterval: Double.infinity)
            
            let task = URLSession.shared.dataTask(with: request) { data, response, error in
                guard let data = data else {
                    print("Conversion error:" + String(describing: error))
                    return
                }
                
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
                                
                                self.eurValue = CGFloat(truncating: NumberFormatter().number(from: actualEurValue)!)
                                self.chfValue = CGFloat(truncating: NumberFormatter().number(from: actualChfValue)!)
                                
                                CacheManager.updateCachedData(data: self.eurValue, key: "eurvalue")
                                CacheManager.updateCachedData(data: self.chfValue, key: "chfvalue")
                                
                                self.didFetchConversion = true
                                
                                var correctValue:CGFloat = self.eurValue
                                var currencySymbol = "€"
                                if UserDefaults.standard.value(forKey: "currency") as? String == "CHF" {
                                    correctValue = self.chfValue
                                    currencySymbol = "CHF"
                                }
                                
                                var balanceValue = String(Int((btcValue*correctValue).rounded()))
                                
                                switch balanceValue.count {
                                case 0..<4:
                                    balanceValue = balanceValue
                                case 4:
                                    balanceValue = balanceValue[0] + " " + balanceValue[1..<4]
                                case 5:
                                    balanceValue = balanceValue[0..<2] + " " + balanceValue[2..<5]
                                case 6:
                                    balanceValue = balanceValue[0..<3] + " " + balanceValue[3..<6]
                                case 7:
                                    balanceValue = balanceValue[0] + " " + balanceValue[1..<4] + " " + balanceValue[4..<7]
                                case 8:
                                    balanceValue = balanceValue[0..<2] + " " + balanceValue[2..<5] + " " + balanceValue[5..<8]
                                case 9:
                                    balanceValue = balanceValue[0..<3] + " " + balanceValue[3..<6] + " " + balanceValue[6..<9]
                                default:
                                    balanceValue = balanceValue
                                }
                                
                                DispatchQueue.main.async {
                                    self.conversionLabel.text = currencySymbol + " " + balanceValue
                                    CacheManager.updateCachedData(data: currencySymbol + " " + balanceValue, key: "conversion")
                                    self.balanceSpinner.stopAnimating()
                                    self.conversionLabel.alpha = 1
                                    
                                    if cachedData == false {
                                        self.setTransactions = self.newTransactions
                                    }
                                    
                                    self.homeTableView.reloadData()
                                    //self.homeTableView.isUserInteractionEnabled = true
                                    self.tableSpinner.stopAnimating()
                                    self.homeTableView.alpha = 1
                                    
                                    // Step 16.
                                    self.calculateProfit(cachedData: cachedData)
                                }
                            }
                        }
                    } catch let error as NSError {
                        print("Conversion error:" + error.localizedDescription)
                    }
                }
            }
            task.resume()
        }
    }
    
    func calculateProfit(cachedData:Bool) {
        
        print("Did start calculating profit.")
        
        self.didStartReset = false
        
        // Step 17.
        
        self.bittrProfitLabel.alpha = 0
        self.bittrProfitSpinner.startAnimating()
        
        let bittrTransactionsCount = self.bittrTransactions.count
        var handledTransactions = 0
        var accumulatedProfit = 0
        var accumulatedInvestments = 0
        var accumulatedCurrentValue = 0
        
        var correctValue:CGFloat = self.eurValue
        var currencySymbol = "€"
        if UserDefaults.standard.value(forKey: "currency") as? String == "CHF" {
            correctValue = self.chfValue
            currencySymbol = "CHF"
        }
        
        if self.setTransactions.count == 0 {
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
            self.yourWalletLabel.text = "your wallet"
            self.yourWalletSpinner.stopAnimating()
            self.yourWalletLabelLeading.constant = -10
        }
        
        // Step 18
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
