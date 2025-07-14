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

    func loadWalletData(currentHeight:Int?, lightningChannels:[ChannelDetails]?, bdkBalance:Int?, canonicalTransactions:[CanonicalTx]?, paymentDetails:[PaymentDetails]?) {
            
            // Ensure CoreVC availability.
            if self.coreVC == nil {
                self.showAlert(presentingController: self.coreVC!, title: Language.getWord(withID: "oops"), message: Language.getWord(withID: "walletconnectfail2"), buttons: [Language.getWord(withID: "okay")], actions: nil)
                return
            }
            
            // Set current blockchain height.
            if let actualCurrentHeight = currentHeight {
                self.coreVC!.bittrWallet.currentHeight = actualCurrentHeight
            }
            
            // Set Lightning channels.
            if let actualLightningChannels = lightningChannels {
                self.coreVC!.bittrWallet.lightningChannels = actualLightningChannels
                
                // Calculate lightning balance by adding up the values of each channel.
                self.coreVC!.bittrWallet.satoshisLightning = 0
                for eachChannel in actualLightningChannels {
                    if eachChannel.outboundCapacityMsat != 0 {
                        self.coreVC!.bittrWallet.satoshisLightning += Int((eachChannel.outboundCapacityMsat / 1000) + (eachChannel.unspendablePunishmentReserve ?? 0))
                    }
                }
                
                // Users can currently only have one channel, their channel with Bittr. So this count is always 0 or 1.
                if actualLightningChannels.count == 1 {
                    // Set Bittr Channel.
                    self.setBittrChannel(withChannel: actualLightningChannels[0])
                }
            }
            
            // Set onchain balance.
            if let actualBdkBalance = bdkBalance {
                self.coreVC!.bittrWallet.satoshisOnchain = actualBdkBalance
            }
            
            // Collect transaction IDs to be checked with Bittr API.
            var txIds = [String]()
            
            // Set onchain transactions.
            var receivedTransactions = [CanonicalTx]()
            if let actualReceivedTransactions = canonicalTransactions {
                receivedTransactions = actualReceivedTransactions
                // Add all onchain transaction IDs.
                for eachTransaction in actualReceivedTransactions {
                    txIds += [eachTransaction.transaction.computeTxid()]
                }
            }
            
            // Add cached Lightning payments to array.
            self.newTransactions.removeAll()
            if let cachedLightningTransactions = CacheManager.getLightningTransactions() {
                self.newTransactions += cachedLightningTransactions
                for eachTransaction in self.newTransactions {
                    self.cachedLightningIds += [eachTransaction.id]
                    if eachTransaction.isSwap {
                        self.cachedLightningIds += [eachTransaction.lightningID]
                        self.cachedLightningIds += [eachTransaction.onchainID]
                        
                        for (index, eachNewTransaction) in self.newTransactions.enumerated() {
                            if eachNewTransaction.id == eachTransaction.lightningID || eachNewTransaction.id == eachTransaction.onchainID {
                                self.newTransactions.remove(at: index)
                            }
                        }
                    }
                }
            }
                
            // Add all Lightning payment IDs that haven't yet been cached.
            var receivedPayments = [PaymentDetails]()
            if let actualReceivedPayments = paymentDetails {
                receivedPayments = actualReceivedPayments
                // Add all lightning payment IDs.
                for eachPayment in actualReceivedPayments {
                    if !self.cachedLightningIds.contains(eachPayment.kind.preimageAsString ?? eachPayment.id) {
                        txIds += [eachPayment.kind.preimageAsString ?? eachPayment.id]
                    }
                }
            }
                
            // Add funding transaction ID.
            if let cachedFundingTxo = CacheManager.getTxoID() {
                txIds += [cachedFundingTxo]
            }
                
            Task {
                // Check whether transactions were Bittr purchases.
                await self.fetchTransactionData(txIds:txIds, sendAll: false)
                
                DispatchQueue.main.async {
                    self.updateTransactionHistory(receivedTransactions: receivedTransactions, receivedPayments: receivedPayments)
                }
            }
    }
    
    
    func updateTransactionHistory(receivedTransactions:[CanonicalTx], receivedPayments:[PaymentDetails]) {
        
        // Create onchain transaction entities.
        for eachTransaction in receivedTransactions {
            if !self.cachedLightningIds.contains(eachTransaction.transaction.computeTxid()) {
                // Onchain transaction isn't part of a previously cached swap transaction.
                let thisTransaction = self.createTransaction(transactionDetails: eachTransaction, paymentDetails: nil, bittrTransaction: nil, coreVC: self.coreVC, bittrTransactions: self.bittrTransactions)
                self.newTransactions += [thisTransaction]
            }
        }
        
        // Create lightning transaction entities.
        for eachPayment in receivedPayments {
            // Add succeeded new payments to table.
            if !self.cachedLightningIds.contains(eachPayment.kind.preimageAsString ?? eachPayment.id), eachPayment.status == .succeeded {
                let thisTransaction = self.createTransaction(transactionDetails: nil, paymentDetails: eachPayment, bittrTransaction: nil, coreVC: self.coreVC, bittrTransactions: self.bittrTransactions)
                self.newTransactions += [thisTransaction]
                CacheManager.storeLightningTransaction(thisTransaction: thisTransaction)
            }
            
            // Make sure there are no duplicate transactions.
            if eachPayment.kind.preimageAsString != nil {
                if self.cachedLightningIds.contains(eachPayment.kind.preimageAsString!), self.cachedLightningIds.contains(eachPayment.id) {
                    for (index, eachTransaction) in self.newTransactions.enumerated().reversed() {
                        if eachTransaction.id == eachPayment.id {
                            self.newTransactions.remove(at: index)
                        }
                    }
                }
            }
        }
        
        // Check for matching swap transactions.
        var swapTransactions = NSMutableDictionary()
        for (index, eachTransaction) in self.newTransactions.enumerated() {
            if eachTransaction.lnDescription.contains("Swap") {
                if var existingTransactions = swapTransactions[eachTransaction.lnDescription] as? [Transaction] {
                    existingTransactions += [eachTransaction]
                    swapTransactions.setValue(existingTransactions, forKey: eachTransaction.lnDescription)
                } else {
                    swapTransactions.setValue([eachTransaction], forKey: eachTransaction.lnDescription)
                }
            }
        }
        for (eachSwapID, eachSetOfTransactions) in swapTransactions {
            if (eachSetOfTransactions as! [Transaction]).count == 2 {
                // Completed swap.
                
                let swapTransaction = Transaction()
                swapTransaction.isSwap = true
                swapTransaction.lnDescription = (eachSwapID as! String)
                swapTransaction.sent = (eachSetOfTransactions as! [Transaction])[0].received + (eachSetOfTransactions as! [Transaction])[1].received - (eachSetOfTransactions as! [Transaction])[0].sent - (eachSetOfTransactions as! [Transaction])[1].sent
                if (eachSwapID as! String).contains("onchain to lightning") {
                    swapTransaction.swapDirection = 0
                    swapTransaction.isLightning = false
                    swapTransaction.id = (eachSwapID as! String).replacingOccurrences(of: "Swap onchain to lightning ", with: "")
                } else {
                    swapTransaction.swapDirection = 1
                    swapTransaction.isLightning = true
                    swapTransaction.id = (eachSwapID as! String).replacingOccurrences(of: "Swap lightning to onchain ", with: "")
                }
                
                for eachTransaction in (eachSetOfTransactions as! [Transaction]) {
                    if eachTransaction.isLightning {
                        // Lightning payment
                        swapTransaction.lightningID = eachTransaction.id
                        swapTransaction.channelId = eachTransaction.channelId
                        if swapTransaction.swapDirection == 0 {
                            // Onchain to Lightning
                            swapTransaction.timestamp = eachTransaction.timestamp
                            swapTransaction.received = eachTransaction.received
                        } else {
                            swapTransaction.sent = eachTransaction.sent
                        }
                    } else {
                        // Onchain transaction
                        swapTransaction.onchainID = eachTransaction.id
                        swapTransaction.boltzSwapId = eachTransaction.boltzSwapId
                        swapTransaction.height = eachTransaction.height
                        if let actualCurrentHeight = self.coreVC?.bittrWallet.currentHeight {
                            swapTransaction.confirmations = (actualCurrentHeight - eachTransaction.height) + 1
                        }
                        if swapTransaction.swapDirection == 1 {
                            // Lightning to Onchain
                            swapTransaction.timestamp = eachTransaction.timestamp
                            swapTransaction.received = eachTransaction.received - eachTransaction.sent
                        } else {
                            swapTransaction.sent = eachTransaction.sent - eachTransaction.received
                        }
                    }
                }
                
                self.newTransactions += [swapTransaction]
                CacheManager.storeLightningTransaction(thisTransaction: swapTransaction)
                
                for (index, eachTransaction) in self.newTransactions.enumerated().reversed() {
                    if eachTransaction.id == swapTransaction.lightningID || eachTransaction.id == swapTransaction.onchainID {
                        self.newTransactions.remove(at: index)
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
        self.setTotalSats(updateTableAfterConversion: true)
    }
    
    
    func setBittrChannel(withChannel:ChannelDetails) {
        
        let thisChannel = Channel()
        thisChannel.id = withChannel.channelId
        thisChannel.received = Int(withChannel.outboundCapacityMsat)/1000
        thisChannel.size = Int(withChannel.channelValueSats)
        thisChannel.punishmentReserve = Int(withChannel.unspendablePunishmentReserve ?? 0)
        thisChannel.sendableMinimum = Int(withChannel.nextOutboundHtlcMinimumMsat)/1000
        thisChannel.receivableMaximum = Int(withChannel.inboundHtlcMaximumMsat ?? 0)/1000
        
        self.coreVC?.bittrWallet.bittrChannel = thisChannel
    }
    
    
    func fetchTransactionData(txIds:[String], sendAll:Bool) async -> Bool {
        
        // Check if transactions were Bittr purchases with the Bittr API.
        
        // Get this user's unique Bittr codes.
        var depositCodes = [String]()
        for eachIbanEntity in self.coreVC!.bittrWallet.ibanEntities {
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
        
        // Create array of transaction IDs to send to Bittr.
        var newTxIds = [String]()
        var newTransactionsWereFound = false
        
        if sendAll {
            // Send all transaction IDs to Bittr again.
            for eachTransaction in self.setTransactions {
                newTxIds += [eachTransaction.id]
            }
        } else {
            // Only send new transaction IDs to Bittr.
            // Collect the txIDs that have not been checked against the Bittr API before.
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
        }
        
        print("TxIds being sent to Bittr: \(newTxIds.count)")
        
        if newTxIds.count == 0 {
            // No new txIDs need to be checked with the Bittr API.
            return false
        } else if depositCodes.count == 0 {
            // There are no deposit codes registered to this device.
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
                            
                            let thisTransaction = self.createTransaction(transactionDetails: nil, paymentDetails: nil, bittrTransaction: eachTransaction, coreVC: self.coreVC, bittrTransactions: self.bittrTransactions)
                            
                            self.newTransactions += [thisTransaction]
                            CacheManager.storeLightningTransaction(thisTransaction: thisTransaction)
                        } else {
                            self.bittrTransactions.setValue(["amount":eachTransaction.purchaseAmount, "currency":eachTransaction.currency], forKey: eachTransaction.txId)
                            
                            if sendAll {
                                // Check transactions that were previously not recognized.
                                for eachExistingTransaction in self.setTransactions {
                                    if eachExistingTransaction.id == eachTransaction.txId, eachExistingTransaction.isBittr == false {
                                        newTransactionsWereFound = true
                                        eachExistingTransaction.isBittr = true
                                        eachExistingTransaction.purchaseAmount = Int(self.stringToNumber(eachTransaction.purchaseAmount))
                                        eachExistingTransaction.currency = eachTransaction.currency
                                        if eachExistingTransaction.isLightning {
                                            CacheManager.storeLightningTransaction(thisTransaction: eachExistingTransaction)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    
                    if sendAll {
                        if newTransactionsWereFound {
                            CacheManager.updateCachedData(data: self.setTransactions, key: "transactions")
                            self.homeTableView.reloadData()
                            return true
                        } else {
                            return false
                        }
                    } else {
                        return true
                    }
                }
            } catch {
                print("Bittr error: \(error.localizedDescription)")
                return false
            }
        }
    }
    
    
    func setTotalSats(updateTableAfterConversion:Bool) {
        
        if self.coreVC == nil {
            self.showAlert(presentingController: self, title: Language.getWord(withID: "oops"), message: Language.getWord(withID: "walletconnectfail2"), buttons: [Language.getWord(withID: "okay")], actions: nil)
            return
        }
        
        // Update bitcoin sign alpha.
        var bitcoinSignAlpha = 0.18
        if CacheManager.darkModeIsOn() {
            bitcoinSignAlpha = 0.35
        }
        
        // Calculate total balance
        let totalBalanceSats = self.coreVC!.bittrWallet.satoshisOnchain + self.coreVC!.bittrWallet.satoshisLightning
        let totalBalanceSatsString = "\(totalBalanceSats)"
        self.balanceWasFetched = true
        
        // Create balance representation with bold satoshis.
        var zeros = "0.00 000 00"
        var numbers = totalBalanceSatsString
        
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
            numbers = "\(CGFloat(totalBalanceSats)/100000000)".replacingOccurrences(of: ",", with: ".")
            let decimalsCount = numbers.split(separator: ".")[1].count
            var decimalsToAdd = 8 - decimalsCount
            while decimalsToAdd > 0 {
                if decimalsToAdd == 6 || decimalsToAdd == 3 {
                    numbers += " 0"
                } else {
                    numbers += "0"
                }
                decimalsToAdd -= 1
            }
            bitcoinSignAlpha = 1
        }
        
        // Set text to invisible label to calculate font size for HTML text.
        self.balanceLabelInvisible.text = "B " + zeros + numbers + " sats"
        let font = self.balanceLabelInvisible.adjustedFont()
        self.satsLabel.font = font
        let adjustedSize = Int(font.pointSize)
        
        // Set HTML balance text.
        var transparentColor = "201, 154, 0"
        var fillColor = "0, 0, 0"
        if CacheManager.darkModeIsOn() {
            transparentColor = "150, 177, 204"
            fillColor = "255, 255, 255"
        }
        self.balanceText = "<center><span style=\"font-family: \'Gilroy-Bold\', \'-apple-system\'; font-size: \(adjustedSize); color: rgb(\(transparentColor)); line-height: 0.5\">\(zeros)</span><span style=\"font-family: \'Gilroy-Bold\', \'-apple-system\'; font-size: \(adjustedSize); color: rgb(\(fillColor)); line-height: 0.5\">\(numbers)</span></center>"
        
        // Store HTML balance text to cache.
        CacheManager.updateCachedData(data: self.balanceText, key: "balance")
        
        if let htmlData = self.balanceText.data(using: .unicode) {
            do {
                let attributedText = try NSAttributedString(data: htmlData, options: [NSAttributedString.DocumentReadingOptionKey.documentType : NSAttributedString.DocumentType.html], documentAttributes: nil)
                balanceLabel.attributedText = attributedText
                balanceLabel.alpha = 1
                bitcoinSign.alpha = bitcoinSignAlpha
                
                // Don't show "sats" label if user has 1 or more bitcoin.
                if bitcoinSignAlpha == 1 {
                    satsLabel.alpha = 0
                    satsLabel.text = ""
                    satsLabelLeading.constant = 0
                } else {
                    satsLabel.alpha = 1
                    satsLabel.text = "sats"
                    satsLabelLeading.constant = 12
                }
                
                // Store satoshis balance string to cache.
                CacheManager.updateCachedData(data: totalBalanceSatsString, key: "satsbalance")
                
                // Convert balance to EUR / CHF.
                self.setConversion(btcValue: CGFloat(totalBalanceSats)/100000000, cachedData: false, updateTableAfterConversion: updateTableAfterConversion)
                
            } catch let e as NSError {
                print("Couldn't fetch text: \(e.localizedDescription)")
            }
        }
    }
    
    
    func setConversion(btcValue:CGFloat, cachedData:Bool, updateTableAfterConversion:Bool) {
        
        if self.coreVC == nil {
            self.showAlert(presentingController: self, title: Language.getWord(withID: "oops"), message: Language.getWord(withID: "walletconnectfail2"), buttons: [Language.getWord(withID: "okay")], actions: nil)
            return
        }
        
        if self.didFetchConversion == true || self.couldNotFetchConversion == true {
            // Conversion rate was already fetched.
            print("Did start currency conversion with cached conversion rate.")
            
            let conversionLabelText = self.updateConversionLabel(btcValue: btcValue)
            
            // Store conversion text to cache.
            CacheManager.updateCachedData(data: conversionLabelText, key: "conversion")
            
            // Show label.
            self.balanceSpinner.stopAnimating()
            self.conversionLabel.alpha = 1
            
            if updateTableAfterConversion {
                if cachedData == false {
                    self.setTransactions = self.newTransactions
                }
                self.updateTableAfterConversion()
                self.calculateProfit(cachedData: cachedData)
            }
        } else {
            // Conversion rate hasn't yet been fetched.
            print("Did start currency conversion.")
            
            self.coreVC!.startSync(type: "conversion")
            
            // TODO: Public?
            var envUrl = "https://getbittr.com/api/price/btc"
            if UserDefaults.standard.value(forKey: "envkey") as? Int == 0 {
                envUrl = "https://model-arachnid-viable.ngrok-free.app/price/btc"
            }
            
            // Get currency conversion rate from Bittr API.
            let request = URLRequest(url: URL(string: envUrl)!,timeoutInterval: Double.infinity)
            let task = URLSession.shared.dataTask(with: request) { data, response, error in
                guard let data = data else {
                    print("Conversion error:" + String(describing: error))
                    
                    DispatchQueue.main.async {
                        self.showAlert(presentingController: self.coreVC!, title: Language.getWord(withID: "oops"), message: Language.getWord(withID: "conversionfail"), buttons: [Language.getWord(withID: "okay")], actions: nil)
                        self.couldNotFetchConversion = true
                        self.setConversion(btcValue: btcValue, cachedData: cachedData, updateTableAfterConversion: updateTableAfterConversion)
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
                                
                                actualEurValue = actualEurValue.fixDecimals()
                                actualChfValue = actualChfValue.fixDecimals()
                                
                                // Set updated conversion rates for EUR and CHF.
                                self.coreVC!.bittrWallet.valueInEUR = self.stringToNumber(actualEurValue)
                                self.coreVC!.bittrWallet.valueInCHF = self.stringToNumber(actualChfValue)
                                
                                // Store updated conversion rates in cache.
                                CacheManager.updateCachedData(data: self.coreVC!.bittrWallet.valueInEUR ?? 0.0, key: "eurvalue")
                                CacheManager.updateCachedData(data: self.coreVC!.bittrWallet.valueInCHF ?? 0.0, key: "chfvalue")
                                
                                self.didFetchConversion = true
                                
                                DispatchQueue.main.async {
                                    
                                    let conversionLabelText = self.updateConversionLabel(btcValue: btcValue)
                                    CacheManager.updateCachedData(data: conversionLabelText, key: "conversion")
                                    
                                    // Show conversion label.
                                    self.balanceSpinner.stopAnimating()
                                    self.conversionLabel.alpha = 1
                                    
                                    if updateTableAfterConversion {
                                        if cachedData == false {
                                            self.setTransactions = self.newTransactions
                                        }
                                        self.updateTableAfterConversion()
                                        self.calculateProfit(cachedData: cachedData)
                                    }
                                    
                                    // Complete sync.
                                    self.coreVC!.completeSync(type: "conversion")
                                }
                            }
                        }
                    } catch let error as NSError {
                        print("Conversion error:" + error.localizedDescription)
                        
                        DispatchQueue.main.async {
                            self.showAlert(presentingController: self.coreVC!, title: Language.getWord(withID: "oops"), message: Language.getWord(withID: "conversionfail"), buttons: [Language.getWord(withID: "okay")], actions: nil)
                            
                            self.couldNotFetchConversion = true
                            self.setConversion(btcValue: btcValue, cachedData: cachedData, updateTableAfterConversion: updateTableAfterConversion)
                            SentrySDK.capture(error: error)
                        }
                    }
                }
            }
            task.resume()
        }
    }
    
    
    func updateConversionLabel(btcValue:CGFloat) -> String {
        
        if self.coreVC == nil { return "" }
        
        // Use preferred currency.
        var correctValue:CGFloat = self.coreVC!.bittrWallet.valueInEUR ?? 0.0
        var currencySymbol = "€"
        if UserDefaults.standard.value(forKey: "currency") as? String == "CHF" {
            correctValue = self.coreVC!.bittrWallet.valueInCHF ?? 0.0
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
            let noTransactionsHTML = "<center><span style=\"font-family: \'Gilroy-Regular\', \'-apple-system\'; font-size: 16; color: rgb(177, 177, 177); line-height: 1.2\">\(Language.getWord(withID: "notransactions1"))</span><span style=\"font-family: \'Gilroy-Bold\', \'-apple-system\'; font-size: 16; color: rgb(177, 177, 177); line-height: 1.2\">\(Language.getWord(withID: "buy"))</span><span style=\"font-family: \'Gilroy-Regular\', \'-apple-system\'; font-size: 16; color: rgb(177, 177, 177); line-height: 1.2\">\(Language.getWord(withID:"notransactions2"))</span></center>"
            
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
        if self.coreVC == nil {
            self.showAlert(presentingController: self, title: Language.getWord(withID: "oops"), message: Language.getWord(withID: "walletconnectfail2"), buttons: [Language.getWord(withID: "okay")], actions: nil)
            return
        }
        
        self.didStartReset = false
        
        // Hide profit label while calculating.
        self.balanceCardGainLabel.alpha = 0
        self.balanceCardProfitView.alpha = 0
        
        // Variables.
        let bittrTransactionsCount = self.bittrTransactions.count
        var handledTransactions = 0
        var accumulatedProfit = 0
        var accumulatedInvestments = 0
        var accumulatedCurrentValue = 0
        
        // Get preferred currency.
        var correctValue:CGFloat = self.coreVC!.bittrWallet.valueInEUR ?? 0.0
        var currencySymbol = "€"
        if UserDefaults.standard.value(forKey: "currency") as? String == "CHF" {
            correctValue = self.coreVC!.bittrWallet.valueInCHF ?? 0.0
            currencySymbol = "CHF"
        }
        
        if self.setTransactions.count == 0 || bittrTransactionsCount == 0 {
            // There are no transactions.
            self.showProfitLabel(currencySymbol: currencySymbol, accumulatedProfit: accumulatedProfit, accumulatedInvestments: accumulatedInvestments, accumulatedCurrentValue: accumulatedCurrentValue)
        } else {
            // There are transactions.
            for eachTransaction in self.setTransactions {
                if eachTransaction.isBittr == true {
                    let transactionValue = CGFloat(eachTransaction.received)/100000000
                    let transactionProfit = Int((transactionValue*correctValue).rounded())-eachTransaction.purchaseAmount
                    
                    accumulatedProfit += transactionProfit
                    accumulatedInvestments += eachTransaction.purchaseAmount
                    accumulatedCurrentValue += Int((transactionValue*correctValue).rounded())
                    
                    handledTransactions += 1
                    
                    if bittrTransactionsCount == handledTransactions {
                        // We're done counting.
                        self.showProfitLabel(currencySymbol: currencySymbol, accumulatedProfit: accumulatedProfit, accumulatedInvestments: accumulatedInvestments, accumulatedCurrentValue: accumulatedCurrentValue)
                    }
                } else {
                    if bittrTransactionsCount == handledTransactions {
                        self.showProfitLabel(currencySymbol: currencySymbol, accumulatedProfit: accumulatedProfit, accumulatedInvestments: accumulatedInvestments, accumulatedCurrentValue: accumulatedCurrentValue)
                    }
                }
            }
        }
        
        if cachedData == false {
            //self.headerLabel.text = Language.getWord(withID: "yourwallet")
            self.headerSpinner.stopAnimating()
            
            if self.couldNotFetchConversion == true {
                self.headerProblemImage.alpha = 1
            }
            
            self.coreVC!.walletHasSynced = true
            self.coreVC!.completeSync(type: "final")
            if self.coreVC!.needsToHandleNotification == true, let actualNotification = self.coreVC!.lightningNotification {
                // Check if it's a swap notification or payment notification
                if let userInfo = actualNotification.userInfo as? [String: Any],
                   let _ = userInfo["swap_id"] as? String {
                    // It's a swap notification
                    self.coreVC!.handleSwapNotificationFromBackground(notification: actualNotification)
                } else {
                    // It's a payment notification
                    self.coreVC!.handlePaymentNotification(notification: actualNotification)
                }
            }
            self.fetchAndPrintPeers()
        } else {
            print("Did calculate cached profits.")
        }
    }
    
    
    func showProfitLabel(currencySymbol:String, accumulatedProfit:Int, accumulatedInvestments:Int, accumulatedCurrentValue:Int) {
        
        if accumulatedInvestments != 0 {
            self.balanceCardGainLabel.text = "\(Int(((CGFloat(accumulatedProfit)/CGFloat(accumulatedInvestments))*100).rounded())) %".replacingOccurrences(of: "-", with: "") //  (\(currencySymbol) \(accumulatedProfit))"
            self.balanceCardGainLabel.alpha = 1
            self.balanceCardProfitView.alpha = 1
        } else {
            self.balanceCardGainLabel.alpha = 1
            self.balanceCardProfitView.alpha = 1
            self.balanceCardGainLabel.text = "0 %"
        }
        
        if accumulatedProfit < 0 {
            // Loss
            self.balanceCardGainLabel.textColor = Colors.getColor("losstext")
            self.balanceCardProfitView.backgroundColor = Colors.getColor("lossbackground0.8")
            self.balanceCardArrowImage.tintColor = Colors.getColor("losstext")
            self.balanceCardArrowImage.image = UIImage(systemName: "arrow.down")
        } else {
            // Profit
            self.balanceCardGainLabel.textColor = Colors.getColor("profittext")
            self.balanceCardProfitView.backgroundColor = Colors.getColor("profitbackground0.8")
            self.balanceCardArrowImage.tintColor = Colors.getColor("profittext")
            self.balanceCardArrowImage.image = UIImage(systemName: "arrow.up")
        }
        
        self.calculatedProfit = accumulatedProfit
        self.calculatedInvestments = accumulatedInvestments
        self.calculatedCurrentValue = accumulatedCurrentValue
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

extension PaymentKind {
    var preimageAsString: String? {
        switch self {
        case .onchain:
            return nil
        case .bolt11(_, let preimage, _):
            return preimage
        case .bolt11Jit(_, let preimage, _, _, _):
            return preimage
        case .spontaneous(_, let preimage):
            return preimage
        //case .bolt12Offer(hash: _, let preimage, secret: _, offerId: _):
        case .bolt12Offer(hash: _, preimage: let preimage, secret: _, offerId: _, payerNote: _, quantity: _):
            return preimage
        //case .bolt12Refund(hash: _, let preimage, secret: _):
        case .bolt12Refund(hash: _, preimage: let preimage, secret: _, payerNote: _, quantity: _):
            return preimage
        }
    }
}

extension UIViewController {
    
    func createTransaction(transactionDetails:CanonicalTx?, paymentDetails:PaymentDetails?, bittrTransaction:BittrTransaction?, coreVC:CoreViewController?, bittrTransactions:NSMutableDictionary?) -> Transaction {
        
        // Create transaction object.
        let thisTransaction = Transaction()
        
        // Check if transaction is onchain, lightning, or a Bittr funding transaction.
        if transactionDetails != nil {
            
            // Onchain transaction.
            thisTransaction.id = transactionDetails!.transaction.computeTxid()
            thisTransaction.note = CacheManager.getTransactionNote(txid: transactionDetails!.transaction.computeTxid())
            do {
                thisTransaction.fee = Int(try LightningNodeService.shared.getWallet()!.calculateFee(tx: transactionDetails!.transaction).toSat())
            } catch {
                print("810 Could not calculate fee.")
            }
            thisTransaction.received = Int(LightningNodeService.shared.getWallet()!.sentAndReceived(tx: transactionDetails!.transaction).received.toSat())
            thisTransaction.sent = Int(LightningNodeService.shared.getWallet()!.sentAndReceived(tx: transactionDetails!.transaction).sent.toSat())
            thisTransaction.isLightning = false
            switch transactionDetails!.chainPosition {
            case .unconfirmed(timestamp: let timestamp):
                thisTransaction.timestamp = Int(timestamp ?? UInt64(Date().timeIntervalSince1970))
                thisTransaction.height = 0
                thisTransaction.confirmations = 0
            case .confirmed(confirmationBlockTime: let confirmationBlockTime, transitively: let transitively):
                thisTransaction.timestamp = Int(confirmationBlockTime.confirmationTime)
                thisTransaction.height = Int(confirmationBlockTime.blockId.height)
                if let actualCurrentHeight = coreVC?.bittrWallet.currentHeight {
                    thisTransaction.confirmations = (actualCurrentHeight - thisTransaction.height) + 1
                }
            }
            
            if CacheManager.getInvoiceDescription(hash: thisTransaction.id) != "" {
                thisTransaction.lnDescription = CacheManager.getInvoiceDescription(hash: thisTransaction.id)
            }
        } else if paymentDetails != nil {
            
            // Lightning payment.
            thisTransaction.id = paymentDetails!.kind.preimageAsString ?? paymentDetails!.id
            thisTransaction.note = CacheManager.getTransactionNote(txid: paymentDetails!.id)
            if paymentDetails!.direction == .inbound {
                thisTransaction.received = Int(paymentDetails!.amountMsat ?? 0)/1000
            } else {
                thisTransaction.sent = Int(paymentDetails!.amountMsat ?? 0)/1000
                thisTransaction.fee = CacheManager.getLightningFees(hash: paymentDetails!.id)
            }
            thisTransaction.isLightning = true
            thisTransaction.timestamp = CacheManager.getInvoiceTimestamp(hash: paymentDetails!.id)
            thisTransaction.lnDescription = CacheManager.getInvoiceDescription(hash: paymentDetails!.id)
            if let actualChannels = coreVC?.bittrWallet.lightningChannels {
                thisTransaction.channelId = actualChannels[0].channelId
            }
        } else if bittrTransaction != nil {
            
            // Bittr funding transaction.
            thisTransaction.id = bittrTransaction!.txId
            thisTransaction.sent = 0
            thisTransaction.received = Int(self.stringToNumber(bittrTransaction!.bitcoinAmount)*100000000)
            thisTransaction.isLightning = true
            thisTransaction.isFundingTransaction = true
            
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS"
            let transactionDate = formatter.date(from:bittrTransaction!.datetime)!
            let transactionTimestamp = Int(transactionDate.timeIntervalSince1970)
            thisTransaction.timestamp = transactionTimestamp
            
            thisTransaction.isBittr = true
            thisTransaction.purchaseAmount = Int(self.stringToNumber(bittrTransaction!.purchaseAmount))
            thisTransaction.currency = bittrTransaction!.currency
            thisTransaction.lnDescription = CacheManager.getInvoiceDescription(hash: bittrTransaction!.txId)
            if let actualChannels = coreVC?.bittrWallet.lightningChannels {
                thisTransaction.channelId = actualChannels[0].channelId
            }
        }
        
        // Check if transaction is Bittr.
        if (bittrTransactions!.allKeys as! [String]).contains(thisTransaction.id), bittrTransaction == nil {
            thisTransaction.isBittr = true
            thisTransaction.purchaseAmount = Int(self.stringToNumber(((bittrTransactions![thisTransaction.id] as! [String:Any])["amount"] as! String)))
            thisTransaction.currency = (bittrTransactions![thisTransaction.id] as! [String:Any])["currency"] as! String
        }
        
        // Return new transaction.
        return thisTransaction
    }
}
