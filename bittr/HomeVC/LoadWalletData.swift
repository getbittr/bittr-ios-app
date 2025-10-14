//
//  LoadWalletData.swift
//  bittr
//
//  Created by Tom Melters on 08/02/2024.
//

import UIKit
import BitcoinDevKit
import LDKNode
import Sentry

extension HomeViewController {

    func loadWalletData() {
        
        // Ensure CoreVC availability.
        if self.coreVC == nil {
            self.showAlert(presentingController: self.coreVC!, title: Language.getWord(withID: "oops"), message: Language.getWord(withID: "walletconnectfail2"), buttons: [Language.getWord(withID: "okay")], actions: nil)
            return
        }
        
        // Calculate lightning balance by adding up the values of each channel.
        if LightningNodeService.shared.ldkNode != nil {
            self.coreVC!.bittrWallet.satoshisLightning = Int(LightningNodeService.shared.ldkNode!.listBalances().totalLightningBalanceSats)
        } else {
            self.coreVC!.bittrWallet.satoshisLightning = 0
            for eachChannel in self.coreVC!.bittrWallet.lightningChannels {
                if eachChannel.outboundCapacityMsat != 0 {
                    self.coreVC!.bittrWallet.satoshisLightning += Int((eachChannel.outboundCapacityMsat / 1000) + (eachChannel.unspendablePunishmentReserve ?? 0))
                }
            }
        }
        
        // Users can currently only have one channel, their channel with Bittr. So this count is always 0 or 1.
        if self.coreVC!.bittrWallet.lightningChannels.count == 1, self.coreVC!.bittrWallet.lightningChannels.first != nil {
            self.setBittrChannel(withChannel: self.coreVC!.bittrWallet.lightningChannels.first!)
        }
        
        // Collect transaction IDs to be checked with Bittr API.
        var txIds = [String]()
        
        // Set onchain transactions.
        var receivedTransactions = [CanonicalTx]()
        if let actualReceivedTransactions = self.coreVC!.bittrWallet.transactionsOnchain {
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
                    
                    for (index, eachNewTransaction) in self.newTransactions.enumerated().reversed() {
                        if eachNewTransaction.id == eachTransaction.lightningID || eachNewTransaction.id == eachTransaction.onchainID {
                            self.newTransactions.remove(at: index)
                        }
                    }
                }
            }
        }
            
        // Add all Lightning payment IDs that haven't yet been cached.
        var receivedPayments = [PaymentDetails]()
        if let actualReceivedPayments = self.coreVC!.bittrWallet.transactionsLightning {
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
                let thisTransaction = eachTransaction.createTransaction(coreVC: self.coreVC, bittrTransactions: self.bittrTransactions)
                self.newTransactions += [thisTransaction]
            }
        }
        
        // Create lightning transaction entities.
        for eachPayment in receivedPayments {
            // Add succeeded new payments to table.
            if !self.cachedLightningIds.contains(eachPayment.kind.preimageAsString ?? eachPayment.id), (eachPayment.status == .succeeded || (eachPayment.status == .pending && eachPayment.direction == .outbound && Int((eachPayment.amountMsat ?? 0)/1000) > 0)) {
                let thisTransaction = eachPayment.createTransaction(coreVC: self.coreVC, bittrTransactions: self.bittrTransactions)
                self.newTransactions += [thisTransaction]
                if eachPayment.status == .succeeded {
                    CacheManager.storeLightningTransaction(thisTransaction: thisTransaction)
                }
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
        self.newTransactions = self.newTransactions.performSwapMatching(coreVC: self.coreVC)
        
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
        if depositCodes.count == 0 {
            print("No TxIds are being sent to Bittr, because there are no deposit codes registered to this device.")
            return false
        }
        
        // Add previously cached transactions to Bittr transactions array.
        self.bittrTransactions.removeAllObjects()
        for eachTransaction in self.lastCachedTransactions {
            if eachTransaction.isBittr == true {
                self.bittrTransactions.setValue(["amount":"\(eachTransaction.purchaseAmount)", "currency":eachTransaction.currency], forKey: eachTransaction.id)
            }
        }
        
        // Create array of transaction IDs to send to Bittr.
        var newTxIds = [String]()
        if sendAll {
            // Send all transaction IDs to Bittr again.
            for eachTransaction in self.setTransactions {
                newTxIds += [eachTransaction.id]
            }
        } else {
            // Only send new transaction IDs to Bittr.
            for eachTxId in txIds {
                if !CacheManager.getSentToBittr().contains(eachTxId) {
                    newTxIds += [eachTxId]
                }
            }
        }
        
        if newTxIds.count == 0 {
            print("There are no new TxIds being sent to Bittr.")
            return false
        } else {
            print("Will send \(newTxIds.count) TxIds to Bittr.")
            do {
                let bittrApiTransactions = try await BittrService.shared.fetchBittrTransactions(txIds: newTxIds, depositCodes: depositCodes)
                print("Bittr transactions: \(bittrApiTransactions.count)")
                
                // Debug: Print the raw API response data for each transaction
                for (index, transaction) in bittrApiTransactions.enumerated() {
                    print("DEBUG - Bittr API transaction \(index + 1):")
                    print("  - txId: \(transaction.txId)")
                    print("  - bitcoinAmount: '\(transaction.bitcoinAmount)'")
                    print("  - purchaseAmount: '\(transaction.purchaseAmount)'")
                    print("  - currency: '\(transaction.currency)'")
                    print("  - transferFee: '\(transaction.transferFee)'")
                    print("  - datetime: '\(transaction.datetime)'")
                }
                
                CacheManager.updateSentToBittr(txids: newTxIds)
                
                if bittrApiTransactions.count == 0 {
                    // There are no Bittr transactions.
                    return false
                } else {
                    // There are Bittr transactions.
                    var newTransactionsWereFound = false
                    
                    for eachTransaction in bittrApiTransactions {
                        if eachTransaction.txId == CacheManager.getTxoID() ?? "" {
                            // This is the funding Txo.
                            let thisTransaction = eachTransaction.createTransaction(coreVC: self.coreVC, isFundingTransaction: true)
                            
                            newTransactionsWereFound = true
                            self.newTransactions += [thisTransaction]
                            CacheManager.storeLightningTransaction(thisTransaction: thisTransaction)
                        } else {
                            self.bittrTransactions.setValue(["amount":eachTransaction.purchaseAmount, "currency":eachTransaction.currency, "transferFee":eachTransaction.transferFee, "bitcoinAmount":eachTransaction.bitcoinAmount], forKey: eachTransaction.txId)
                            
                            if sendAll {
                                // Check transactions that were previously not recognized.
                                for eachExistingTransaction in self.setTransactions {
                                    if eachExistingTransaction.id == eachTransaction.txId {
                                        newTransactionsWereFound = true
                                        eachExistingTransaction.isBittr = true
                                        eachExistingTransaction.purchaseAmount = eachTransaction.purchaseAmount.toNumber()
                                        eachExistingTransaction.currency = eachTransaction.currency
                                        let transferFee = eachTransaction.transferFee.toNumber().inSatoshis()
                                        eachExistingTransaction.transferFee = CGFloat(transferFee)
                                        
                                        // Update the received amount with the correct bitcoinAmount from Bittr API
                                        let correctBitcoinAmount = eachTransaction.bitcoinAmount.toNumber().inSatoshis()
                                        eachExistingTransaction.received = correctBitcoinAmount
                                        print("DEBUG - Updated existing transaction \(eachTransaction.txId) with correct amount: \(correctBitcoinAmount) sats")
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
                        }
                        return newTransactionsWereFound
                    } else {
                        return true
                    }
                }
            } catch {
                print("Bittr error: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    SentrySDK.capture(error: error) { scope in
                        scope.setExtra(value: "LoadWalletData row 266", key: "context")
                    }
                }
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
        var bitcoinSignAlpha = CacheManager.darkModeIsOn() ? 0.35 : 0.18
        
        // Calculate total balance
        let totalBalanceSats = self.coreVC!.bittrWallet.satoshisOnchain + self.coreVC!.bittrWallet.satoshisLightning
        let totalBalanceSatsString = "\(totalBalanceSats)"
        self.balanceWasFetched = true
        
        // Create balance representation with bold satoshis.
        let allZeros = ["", "0.00 000 00", "0.00 000 0", "0.00 000 ", "0.00 00", "0.00 0", "0.00 ", "0.0", "0."]
        var zeros = ""
        var numbers = totalBalanceSatsString.addSpaces()
        
        if totalBalanceSatsString.count < 9 {
            zeros = allZeros[totalBalanceSatsString.count]
        } else {
            numbers = "\(totalBalanceSats.inBTC())".replacingOccurrences(of: ",", with: ".")
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
        let transparentColor = CacheManager.darkModeIsOn() ? "150, 177, 204" : "201, 154, 0"
        let fillColor = CacheManager.darkModeIsOn() ? "255, 255, 255" : "0, 0, 0"
        self.balanceText = "<center><span style=\"font-family: \'Gilroy-Bold\', \'-apple-system\'; font-size: \(adjustedSize); color: rgb(\(transparentColor)); line-height: 0.5\">\(zeros)</span><span style=\"font-family: \'Gilroy-Bold\', \'-apple-system\'; font-size: \(adjustedSize); color: rgb(\(fillColor)); line-height: 0.5\">\(numbers)</span></center>"
        
        // Store HTML balance text to cache.
        CacheManager.updateCachedData(data: self.balanceText, key: "balance")
        
        if let htmlData = self.balanceText.data(using: .unicode) {
            do {
                let attributedText = try NSAttributedString(data: htmlData, options: [NSAttributedString.DocumentReadingOptionKey.documentType : NSAttributedString.DocumentType.html], documentAttributes: nil)
                self.balanceLabel.attributedText = attributedText
                self.balanceLabel.alpha = 1
                self.bitcoinSign.alpha = bitcoinSignAlpha
                
                // Don't show "sats" label if user has 1 or more bitcoin.
                if bitcoinSignAlpha == 1 {
                    self.satsLabel.alpha = 0
                    self.satsLabel.text = ""
                    self.satsLabelLeading.constant = 0
                } else {
                    self.satsLabel.alpha = 1
                    self.satsLabel.text = "sats"
                    self.satsLabelLeading.constant = 12
                }
                
                // Store satoshis balance string to cache.
                CacheManager.updateCachedData(data: totalBalanceSatsString, key: "satsbalance")
                
                // Convert balance to EUR / CHF.
                self.setConversion(btcValue: totalBalanceSats.inBTC(), cachedData: false, updateTableAfterConversion: updateTableAfterConversion)
                
                // Start timer
                if self.coreVC!.walletSync == nil {
                    self.coreVC!.walletSync = BackgroundSync()
                    self.coreVC!.walletSync!.start()
                }
                
            } catch {
                print("Couldn't fetch text: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    SentrySDK.capture(error: error) { scope in
                        scope.setExtra(value: "LoadWalletData row 360", key: "context")
                    }
                }
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
            
            self.coreVC!.startSync(type: .conversion)
            
            Task {
                await CallsManager.makeApiCall(url: "https://getbittr.com/api/price/btc", parameters: nil, getOrPost: "GET") { result in
                    DispatchQueue.main.async {
                        switch result {
                        case .success(let receivedDictionary):
                            if var actualEurValue = receivedDictionary["btc_eur"] as? String, var actualChfValue = receivedDictionary["btc_chf"] as? String {
                                
                                actualEurValue = actualEurValue.fixDecimals()
                                actualChfValue = actualChfValue.fixDecimals()
                                
                                // Set updated conversion rates for EUR and CHF.
                                self.coreVC!.bittrWallet.valueInEUR = actualEurValue.toNumber()
                                self.coreVC!.bittrWallet.valueInCHF = actualChfValue.toNumber()
                                
                                // Store updated conversion rates in cache.
                                CacheManager.updateCachedData(data: self.coreVC!.bittrWallet.valueInEUR ?? 0.0, key: "eurvalue")
                                CacheManager.updateCachedData(data: self.coreVC!.bittrWallet.valueInCHF ?? 0.0, key: "chfvalue")
                                
                                self.didFetchConversion = true
                                
                                let conversionLabelText = self.updateConversionLabel(btcValue: btcValue)
                                CacheManager.updateCachedData(data: conversionLabelText, key: "conversion")
                                
                                // Show conversion label.
                                self.conversionLabel.alpha = 1
                                
                                if updateTableAfterConversion {
                                    if cachedData == false {
                                        self.setTransactions = self.newTransactions
                                    }
                                    self.updateTableAfterConversion()
                                    self.calculateProfit(cachedData: cachedData)
                                }
                                
                                // Complete sync.
                                self.coreVC!.completeSync(type: .conversion)
                            } else {
                                self.showAlert(presentingController: self.coreVC!, title: Language.getWord(withID: "oops"), message: Language.getWord(withID: "conversionfail"), buttons: [Language.getWord(withID: "okay")], actions: nil)
                                self.couldNotFetchConversion = true
                                self.setConversion(btcValue: btcValue, cachedData: cachedData, updateTableAfterConversion: updateTableAfterConversion)
                                SentrySDK.capture(message: "Received unexpected data from conversion API.")
                            }
                        case .failure(let error):
                            self.showAlert(presentingController: self.coreVC!, title: Language.getWord(withID: "oops"), message: Language.getWord(withID: "conversionfail"), buttons: [Language.getWord(withID: "okay")], actions: nil)
                            self.couldNotFetchConversion = true
                            self.setConversion(btcValue: btcValue, cachedData: cachedData, updateTableAfterConversion: updateTableAfterConversion)
                            SentrySDK.capture(error: error) { scope in
                                scope.setExtra(value: "LoadWalletData row 447", key: "context")
                            }
                        }
                    }
                }
            }
        }
    }
    
    
    func updateConversionLabel(btcValue:CGFloat) -> String {
        
        if self.coreVC == nil { return "" }
        
        // Use preferred currency.
        let bitcoinValue = self.getCorrectBitcoinValue(coreVC: self.coreVC!)
        
        // Converted balance string.
        let balanceValue = String(Int((btcValue*bitcoinValue.currentValue).rounded())).addSpaces()
        
        // Set conversion label.
        self.conversionLabel.text = bitcoinValue.chosenCurrency + " " + balanceValue
        
        return self.conversionLabel.text ?? ""
    }
    
    
    func updateTableAfterConversion() {
        
        self.homeTableView.reloadData()
        self.homeTableView.alpha = 1
        
        if self.setTransactions.count == 0 {
            let noTransactionsHTML = "<center><span style=\"font-family: \'Gilroy-Regular\', \'-apple-system\'; font-size: 16; color: rgb(177, 177, 177); line-height: 1.2\">\(Language.getWord(withID: "notransactions1"))</span><span style=\"font-family: \'Gilroy-Bold\', \'-apple-system\'; font-size: 16; color: rgb(177, 177, 177); line-height: 1.2\">\(Language.getWord(withID: "buy"))</span><span style=\"font-family: \'Gilroy-Regular\', \'-apple-system\'; font-size: 16; color: rgb(177, 177, 177); line-height: 1.2\">\(Language.getWord(withID:"notransactions2"))</span></center>"
            
            if let htmlData = noTransactionsHTML.data(using: .unicode) {
                do {
                    let attributedText = try NSAttributedString(data: htmlData, options: [NSAttributedString.DocumentReadingOptionKey.documentType : NSAttributedString.DocumentType.html], documentAttributes: nil)
                    self.noTransactionsLabel.attributedText = attributedText
                    self.noTransactionsLabel.alpha = 1
                } catch {
                    print("Couldn't fetch text: \(error.localizedDescription)")
                    DispatchQueue.main.async {
                        SentrySDK.capture(error: error) { scope in
                            scope.setExtra(value: "LoadWalletData row 489", key: "context")
                        }
                    }
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
        let bitcoinValue = self.getCorrectBitcoinValue(coreVC: self.coreVC!)
        
        if self.setTransactions.count == 0 || bittrTransactionsCount == 0 {
            // There are no transactions.
            self.showProfitLabel(currencySymbol: bitcoinValue.chosenCurrency, accumulatedProfit: accumulatedProfit, accumulatedInvestments: accumulatedInvestments, accumulatedCurrentValue: accumulatedCurrentValue)
        } else {
            // There are transactions.
            for eachTransaction in self.setTransactions {
                if eachTransaction.isBittr == true {
                    let transactionValue = eachTransaction.received.inBTC()
                    let transactionProfit = Int((transactionValue*bitcoinValue.currentValue).rounded())-Int(eachTransaction.purchaseAmount.rounded())
                    
                    accumulatedProfit += transactionProfit
                    accumulatedInvestments += Int(eachTransaction.purchaseAmount.rounded())
                    accumulatedCurrentValue += Int((transactionValue*bitcoinValue.currentValue).rounded())
                    
                    handledTransactions += 1
                    
                    if bittrTransactionsCount == handledTransactions {
                        // We're done counting.
                        self.showProfitLabel(currencySymbol: bitcoinValue.chosenCurrency, accumulatedProfit: accumulatedProfit, accumulatedInvestments: accumulatedInvestments, accumulatedCurrentValue: accumulatedCurrentValue)
                    }
                } else {
                    if bittrTransactionsCount == handledTransactions {
                        self.showProfitLabel(currencySymbol: bitcoinValue.chosenCurrency, accumulatedProfit: accumulatedProfit, accumulatedInvestments: accumulatedInvestments, accumulatedCurrentValue: accumulatedCurrentValue)
                    }
                }
            }
        }
        
        if cachedData == false {
            self.headerSpinner.stopAnimating()
            
            // Check if conversion rates have been fetched successfully.
            if self.couldNotFetchConversion {
                self.headerProblemImage.alpha = 1
            }
            
            // Stop sync status spinner.
            self.coreVC!.walletHasSynced = true
            self.coreVC!.completeSync(type: .final)
            
            // Check if notification needs handling.
            if self.coreVC!.needsToHandleNotification, let actualNotification = self.coreVC!.lightningNotification {
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
            
            // Check if peer connection has been successful.
            self.fetchAndPrintPeers()
            
            // Check if wallet is being removed from device.
            if self.coreVC!.resettingPin, self.coreVC!.genericSpinner.isAnimating {
                // We're removing the wallet from the device.
                let restoreButton = UIButton()
                restoreButton.accessibilityIdentifier = "restore"
                self.coreVC!.settingsVC!.settingsTapped(restoreButton)
            }
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
        case .bolt12Offer(hash: _, preimage: let preimage, secret: _, offerId: _, payerNote: _, quantity: _):
            return preimage
        case .bolt12Refund(hash: _, preimage: let preimage, secret: _, payerNote: _, quantity: _):
            return preimage
        }
    }
}

extension [Transaction] {
    
    func performSwapMatching(coreVC:CoreViewController?) -> [Transaction] {
        
        // Create a mutable array of Transactions.
        var currentTransactions = self
        
        // Look for lightning and onchain transactions with matching swap descriptions
        let swapTransactions = NSMutableDictionary()
        
        for eachTransaction in currentTransactions {
            if eachTransaction.lnDescription.contains("Swap") {
                if var existingTransactions = swapTransactions[eachTransaction.lnDescription] as? [Transaction] {
                    existingTransactions += [eachTransaction]
                    swapTransactions.setValue(existingTransactions, forKey: eachTransaction.lnDescription)
                } else {
                    swapTransactions.setValue([eachTransaction], forKey: eachTransaction.lnDescription)
                }
            }
        }
        
        // Process completed swaps
        for (eachSwapID, eachSetOfTransactions) in swapTransactions {
            if (eachSetOfTransactions as! [Transaction]).count == 2 {
                // Completed swap.
                print("Found completed swap: \(eachSwapID)")
                
                if (eachSwapID as! String).contains((eachSetOfTransactions as! [Transaction])[0].id), (eachSetOfTransactions as! [Transaction])[0].swapStatus == .succeeded {
                    // This is already a completed Swap transaction.
                    for (index, eachTransaction) in currentTransactions.enumerated().reversed() {
                        if (eachSetOfTransactions as! [Transaction])[1].id == eachTransaction.id {
                            currentTransactions.remove(at: index)
                        }
                    }
                    CacheManager.storeLightningTransaction(thisTransaction: (eachSetOfTransactions as! [Transaction])[0])
                } else if (eachSwapID as! String).contains((eachSetOfTransactions as! [Transaction])[1].id), (eachSetOfTransactions as! [Transaction])[1].swapStatus == .succeeded {
                    // This is already a completed Swap transaction.
                    for (index, eachTransaction) in currentTransactions.enumerated().reversed() {
                        if (eachSetOfTransactions as! [Transaction])[0].id == eachTransaction.id {
                            currentTransactions.remove(at: index)
                        }
                    }
                    CacheManager.storeLightningTransaction(thisTransaction: (eachSetOfTransactions as! [Transaction])[1])
                } else {
                    
                    let swapTransaction = Transaction()
                    swapTransaction.isSwap = true
                    swapTransaction.boltzSwapId = CacheManager.getSwapID(dateID: eachSwapID as! String) ?? "Unavailable"
                    swapTransaction.lnDescription = (eachSwapID as! String)
                    
                    swapTransaction.sent = (eachSetOfTransactions as! [Transaction])[0].received + (eachSetOfTransactions as! [Transaction])[1].received - (eachSetOfTransactions as! [Transaction])[0].sent - (eachSetOfTransactions as! [Transaction])[1].sent
                    
                    if (eachSwapID as! String).contains("onchain to lightning") {
                        swapTransaction.swapDirection = .onchainToLightning
                        swapTransaction.isLightning = false
                        swapTransaction.id = (eachSwapID as! String).replacingOccurrences(of: "Swap onchain to lightning ", with: "")
                    } else {
                        swapTransaction.swapDirection = .lightningToOnchain
                        swapTransaction.isLightning = true
                        swapTransaction.id = (eachSwapID as! String).replacingOccurrences(of: "Swap lightning to onchain ", with: "")
                    }
                    
                    for eachTransaction in (eachSetOfTransactions as! [Transaction]) {
                        if eachTransaction.isLightning {
                            // Lightning payment
                            if eachTransaction.isSwap {
                                swapTransaction.lightningID = eachTransaction.lightningID
                            } else {
                                swapTransaction.lightningID = eachTransaction.id
                            }
                            swapTransaction.channelId = eachTransaction.channelId
                            if swapTransaction.swapDirection == .onchainToLightning {
                                swapTransaction.timestamp = eachTransaction.timestamp
                                swapTransaction.received = eachTransaction.received
                            } else {
                                swapTransaction.sent = eachTransaction.sent
                            }
                        } else {
                            // Onchain transaction
                            if eachTransaction.isSwap {
                                swapTransaction.onchainID = eachTransaction.onchainID
                            } else {
                                swapTransaction.onchainID = eachTransaction.id
                            }
                            swapTransaction.height = eachTransaction.height
                            if let actualCurrentHeight = coreVC?.bittrWallet.currentHeight {
                                swapTransaction.confirmations = (actualCurrentHeight - eachTransaction.height) + 1
                            }
                            if swapTransaction.swapDirection == .lightningToOnchain {
                                swapTransaction.timestamp = eachTransaction.timestamp
                                swapTransaction.received = eachTransaction.received - eachTransaction.sent
                            } else {
                                swapTransaction.sent = eachTransaction.sent - eachTransaction.received
                            }
                        }
                    }
                    
                    if !(eachSetOfTransactions as! [Transaction])[0].isLightning, !(eachSetOfTransactions as! [Transaction])[1].isLightning {
                        // Both transactions are onchain. This is a failed normal swap.
                        swapTransaction.timestamp = (eachSetOfTransactions as! [Transaction])[0].timestamp
                        swapTransaction.sent = (eachSetOfTransactions as! [Transaction])[0].sent + (eachSetOfTransactions as! [Transaction])[1].sent
                        swapTransaction.received = (eachSetOfTransactions as! [Transaction])[0].received + (eachSetOfTransactions as! [Transaction])[1].received
                        swapTransaction.swapStatus = .failed
                        
                        if ((eachSetOfTransactions as! [Transaction])[0].received - (eachSetOfTransactions as! [Transaction])[0].sent) < ((eachSetOfTransactions as! [Transaction])[1].received - (eachSetOfTransactions as! [Transaction])[1].sent) {
                            // The 2nd transaction is the refund.
                            swapTransaction.onchainID = (eachSetOfTransactions as! [Transaction])[0].id
                            swapTransaction.lightningID = (eachSetOfTransactions as! [Transaction])[1].id
                        } else {
                            // The 1st transaction is the refund.
                            swapTransaction.onchainID = (eachSetOfTransactions as! [Transaction])[1].id
                            swapTransaction.lightningID = (eachSetOfTransactions as! [Transaction])[0].id
                        }
                    }
                    
                    // Remove the individual transactions and add the combined swap transaction
                    let transactionIDs = [(eachSetOfTransactions as! [Transaction])[0].id, (eachSetOfTransactions as! [Transaction])[1].id]
                    for (index, eachTransaction) in currentTransactions.enumerated().reversed() {
                        if transactionIDs.contains(eachTransaction.id) {
                            currentTransactions.remove(at: index)
                        }
                    }
                    
                    currentTransactions += [swapTransaction]
                    CacheManager.storeLightningTransaction(thisTransaction: swapTransaction)
                }
            } else if (eachSetOfTransactions as! [Transaction]).count == 1, !(eachSetOfTransactions as! [Transaction])[0].isSwap {
                // These are pending swap transactions.
                print("Found pending swap: \(eachSwapID)")
                
                let swapTransaction = Transaction()
                swapTransaction.isSwap = true
                swapTransaction.swapStatus = .pending
                swapTransaction.boltzSwapId = CacheManager.getSwapID(dateID: eachSwapID as! String) ?? "Unavailable"
                swapTransaction.lnDescription = (eachSwapID as! String)
                
                swapTransaction.timestamp = (eachSetOfTransactions as! [Transaction])[0].timestamp
                swapTransaction.sent = (eachSetOfTransactions as! [Transaction])[0].sent
                swapTransaction.received = (eachSetOfTransactions as! [Transaction])[0].received
                swapTransaction.isLightning = (eachSetOfTransactions as! [Transaction])[0].isLightning
                swapTransaction.id = (eachSwapID as! String).replacingOccurrences(of: "Swap lightning to onchain ", with: "").replacingOccurrences(of: "Swap onchain to lightning ", with: "")
                
                if (eachSwapID as! String).contains("onchain to lightning") {
                    swapTransaction.swapDirection = .onchainToLightning
                } else {
                    swapTransaction.swapDirection = .lightningToOnchain
                }
                
                if swapTransaction.isLightning {
                    swapTransaction.lightningID = (eachSetOfTransactions as! [Transaction])[0].id
                    swapTransaction.channelId = (eachSetOfTransactions as! [Transaction])[0].channelId
                } else {
                    swapTransaction.onchainID = (eachSetOfTransactions as! [Transaction])[0].id
                    swapTransaction.height = (eachSetOfTransactions as! [Transaction])[0].height
                    if let actualCurrentHeight = coreVC?.bittrWallet.currentHeight {
                        swapTransaction.confirmations = (actualCurrentHeight - swapTransaction.height) + 1
                    }
                }
                
                // Remove the individual transactions and add the combined swap transaction
                for (index, eachTransaction) in currentTransactions.enumerated().reversed() {
                    if eachTransaction.id == (eachSetOfTransactions as! [Transaction])[0].id {
                        currentTransactions.remove(at: index)
                    }
                }
                
                currentTransactions += [swapTransaction]
            }
        }
        
        return currentTransactions
    }
}
