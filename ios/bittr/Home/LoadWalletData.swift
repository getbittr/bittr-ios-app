//
//  LoadWalletData.swift
//  bittr
//
//  Created by Tom Melters on 08/02/2024.
//

import UIKit
import LDKNode

extension HomeViewController {

    func loadWalletData() {

        // Take the node handle up front — everything below reads through it, and
        // bailing halfway (after caching a txo ID, before any of the balances)
        // leaves the cache describing a snapshot we never applied.
        guard let node = BitcoinManager.shared.ldkNode else { return }

        // Get channels, balance, and funding transaction ID.
        var satoshisLightning = 0
        let lightningChannels = BitcoinManager.shared.listChannels()
        if let activeChannel = lightningChannels.getActiveChannel() {
            if let channelTxo = activeChannel.fundingTxo {
                CacheManager.storeTxoID(txoID: channelTxo.txid)
                CacheManager.storeChannelFundingOutpoint(txID: channelTxo.txid, vout: channelTxo.vout)
            }
            if Int(activeChannel.outboundCapacityMsat/1000) != 0 {
                // Channel balance is more than punishment reserve.
                satoshisLightning += Int((activeChannel.outboundCapacityMsat / 1000) + (activeChannel.unspendablePunishmentReserve ?? 0))
            } else {
                // Channel balance is less than punishment reserve.
                satoshisLightning += Int(activeChannel.channelValueSats - activeChannel.inboundCapacityMsat/1000 - activeChannel.counterpartyUnspendablePunishmentReserve)
            }
        }
        
        // Get transactions.
        let allTransactions = BitcoinManager.shared.listPayments()
        
        // Get onchain balance.
        let balances = node.listBalances()
        let satoshisOnchain = Int(balances.totalOnchainBalanceSats)
        let satoshisOnchainSpendable = Int(balances.spendableOnchainBalanceSats)
        
        // Gather pending lightning balances.
        let pendingBalancesFromChannelClosures = balances.pendingClosureSatoshis(openChannelIds: lightningChannels.map { $0.channelId })
        
        // Store channel closure txIDs.
        CacheManager.storeChannelClosureTxIDs(txIDs: balances.pendingBalancesFromChannelClosures.spendingTxIDs())
        
        if pendingBalancesFromChannelClosures > 0 {
            // A force-close has happened. No need to hold on to the funding outpoint.
            CacheManager.removeChannelFundingOutpoint()
        }
        
        // Apply the snapshot to the shared wallet on the main thread.
        let apply = {
            BitcoinManager.shared.bittrWallet.satoshisLightning = satoshisLightning
            BitcoinManager.shared.bittrWallet.pendingBalancesFromChannelClosures = pendingBalancesFromChannelClosures
            BitcoinManager.shared.bittrWallet.lightningChannels = lightningChannels
            BitcoinManager.shared.bittrWallet.allTransactions = allTransactions
            BitcoinManager.shared.bittrWallet.satoshisOnchain = satoshisOnchain
            BitcoinManager.shared.bittrWallet.satoshisOnchainSpendable = satoshisOnchainSpendable

            Task {
                // Check whether transactions were Bittr purchases.
                _ = await self.getBittrTransactionDetails()

                DispatchQueue.main.async {
                    self.updateTransactionHistory()
                }
            }
        }
        
        if Thread.isMainThread {
            apply()
        } else {
            DispatchQueue.main.async(execute: apply)
        }
    }
    
    
    func updateTransactionHistory() {
        
        // Add cached Lightning payments to array.
        self.newTransactions = CacheManager.getLightningTransactions()
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
        
        // Create new transaction entities.
        for eachPayment in BitcoinManager.shared.bittrWallet.allTransactions {
            // Add succeeded new payments to table.
            if !self.cachedLightningIds.contains(eachPayment.kind.transactionID ?? eachPayment.id), (eachPayment.hasSucceeded() || eachPayment.isPendingOutbound() || eachPayment.isUnconfirmedOnchainInbound()) {
                
                // Create transaction.
                let thisTransaction = eachPayment.createTransaction(bittrTransactions: self.bittrTransactions)
                self.newTransactions += [thisTransaction]
                
                // Cache succeeded Lightning payments.
                if thisTransaction.isLightning, eachPayment.status == .succeeded {
                    CacheManager.storeLightningTransaction(thisTransaction)
                }
            }
            
            // Make sure there are no duplicate transactions.
            if eachPayment.kind.transactionID != nil, self.cachedLightningIds.contains(eachPayment.kind.transactionID!), self.cachedLightningIds.contains(eachPayment.id) {
                for (index, eachTransaction) in self.newTransactions.enumerated().reversed() where eachTransaction.id == eachPayment.id {
                    self.newTransactions.remove(at: index)
                }
            }
        }
        
        // Check for matching swap transactions.
        self.newTransactions = self.newTransactions.performSwapMatching()
        
        // Sort all transactions by date/time.
        self.newTransactions.sort { transaction1, transaction2 in
            transaction1.timestamp > transaction2.timestamp
        }
        
        // Store transactions in cache.
        CacheManager.cachedHomeTransactions = self.newTransactions
        
        // Update balance label.
        self.setTotalSats()
        
        // Update table.
        self.visibleTransactions = self.newTransactions
        self.reloadTransactionsTable()
        
        // Calculate profits.
        self.calculateProfit()
        
        if (self.coreVC != nil && !self.coreVC!.walletHasSynced) {
            // Finalize sync.
            self.finalizeSync()
        } else if self.coreVC != nil, (self.coreVC!.resettingPin || self.coreVC!.removingWalletForIncorrectPin), self.coreVC!.genericSpinner.isAnimating {
            // User is locked out and is retrying removing their wallet.
            self.coreVC!.restoreWalletTapped()
        }
    }
    
    
    func getBittrTransactionDetails() async -> Bool {
        // Check if transactions were Bittr purchases with the Bittr API.
        
        // Get this user's unique Bittr codes.
        var depositCodes = [String]()
        for eachIbanEntity in BitcoinManager.shared.bittrWallet.ibanEntities where eachIbanEntity.yourUniqueCode != "" {
            depositCodes += [eachIbanEntity.yourUniqueCode]
        }
        if depositCodes.count == 0 {
            Log.info("No TxIds are being sent to Bittr, because there are no deposit codes registered to this device.")
            return false
        }
        
        // Create array of transaction IDs to send to Bittr.
        // Only send new transaction IDs to Bittr.
        var sendableTxIDs = [String]()
            
        // Add all lightning payment IDs.
        for eachPayment in BitcoinManager.shared.bittrWallet.allTransactions {
            let txID = eachPayment.kind.transactionID ?? eachPayment.id
            if eachPayment.status == .succeeded, eachPayment.direction == .inbound, !CacheManager.getSentToBittr().contains(txID) {
                sendableTxIDs += [txID]
            }
        }
        
        // Add funding transaction ID.
        if let cachedFundingTxID = CacheManager.getTxoID(),
            !(CacheManager.getSentToBittr().contains(cachedFundingTxID) &&
            self.visibleTransactions.contains(where: { transaction in transaction.id == cachedFundingTxID})) {
            sendableTxIDs += [cachedFundingTxID]
        }
        
        // Add previously cached transactions to Bittr transactions array.
        self.bittrTransactions = [:]
        for eachTransaction in (CacheManager.cachedHomeTransactions ?? [Transaction]()) where eachTransaction.isBittr {
            self.bittrTransactions.updateValue(eachTransaction.toBittrTransaction(), forKey: eachTransaction.id)
        }
        
        // Check if any IDs need to be sent.
        if sendableTxIDs.count == 0 {
            Log.info("There are no new TxIds being sent to Bittr.")
            return false
        }
        
        Log.info("Will send \(sendableTxIDs.count) TxIds to Bittr.")
        let bittrApiTransactions:[BittrTransaction]
        do {
            bittrApiTransactions = try await BittrService.shared.fetchBittrTransactions(txIds: sendableTxIDs, depositCodes: depositCodes)
            Log.info("Bittr transactions: \(bittrApiTransactions.count)")
        } catch {
            Log.info("Bittr error: \(error.localizedDescription)")
            SentryManager.capture(error, context: "LoadWalletData row 266")
            return false
        }
        
        CacheManager.updateSentToBittr(txids: sendableTxIDs)
        
        if bittrApiTransactions.count == 0 {
            // There are no Bittr transactions.
            return false
        }
        
        for eachTransaction in bittrApiTransactions {
            self.bittrTransactions.updateValue(eachTransaction, forKey: eachTransaction.txId)
            
            if let cachedFundingTxID = CacheManager.getTxoID(), eachTransaction.txId == cachedFundingTxID {
                // This is a channel funding transaction.
                let thisTransaction = eachTransaction.createTransaction(isFundingTransaction: true)
                self.newTransactions += [thisTransaction]
                CacheManager.storeLightningTransaction(thisTransaction)
            }
        }
        
        return true
    }
    
    
    func setTotalSats() {
        // Calculate total balance
        let totalBalanceSats = BitcoinManager.shared.bittrWallet.satoshisOnchain + BitcoinManager.shared.bittrWallet.satoshisLightning + BitcoinManager.shared.bittrWallet.pendingBalancesFromChannelClosures
        let totalBalanceSatsString = "\(totalBalanceSats)"
        
        // Load balance label.
        CacheManager.cachedSatsBalance = totalBalanceSatsString
        self.loadBalanceLabel(amount: totalBalanceSatsString)
        
        // Convert balance to EUR / CHF.
        self.setConversion()
    }
    
    func loadBalanceLabel(amount:String) {
        
        let satoshis = Int(amount) ?? 0
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
        self.balanceLabel.alpha = 1
        self.bitcoinSign.alpha = isWholeBitcoin ? 1 : (CacheManager.darkModeIsOn() ? 0.47 : 0.18)
    }
    
    
    func setConversion() {
        
        // Set, cache, and show conversion label.
        let cachedBtcBalance = (CacheManager.cachedSatsBalance ?? "0").toNumber().inBTC()
        let conversionLabelText = self.updateConversionLabel(btcValue: cachedBtcBalance)
        CacheManager.cachedConversion = conversionLabelText
        
        // Only reveal the conversion once the balance is known.
        self.conversionLabel.alpha = self.balanceLabel.alpha
    }
    
    
    func didFetchConversionRates() async -> Bool {
        Log.info("Will download conversion rates.")
        
        let receivedDictionary:NSDictionary
        do {
            receivedDictionary = try await withCheckedThrowingContinuation { continuation in
                Task {
                    await CallsManager.makeApiCall(url: "https://getbittr.com/api/price/btc", parameters: nil, getOrPost: .get) { result in
                        DispatchQueue.main.async {
                            switch result {
                            case .success(let receivedDictionary):
                                continuation.resume(returning: receivedDictionary)
                            case .failure(let error):
                                continuation.resume(throwing: error)
                            }
                        }
                    }
                }
            }
        } catch {
            SentryManager.capture(error, context: "LoadWalletData row 394")
            Log.info("Could not download conversion rates.")
            return false
        }
        
        guard
            let actualEurValue = receivedDictionary["btc_eur"] as? String,
            let actualChfValue = receivedDictionary["btc_chf"] as? String
        else {
            Log.info("Could not download conversion rates.")
            SentryManager.capture("Received unexpected data from conversion API.")
            return false
        }
            
        // Set updated conversion rates for EUR and CHF.
        BitcoinManager.shared.bittrWallet.valueInEUR = actualEurValue.fixDecimals().toNumber()
        BitcoinManager.shared.bittrWallet.valueInCHF = actualChfValue.fixDecimals().toNumber()
        
        // Store updated conversion rates in cache.
        CacheManager.cachedEurValue = BitcoinManager.shared.bittrWallet.valueInEUR ?? 0.0
        CacheManager.cachedChfValue = BitcoinManager.shared.bittrWallet.valueInCHF ?? 0.0
        
        Log.info("Did successfully download conversion rates.")
        return true
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
    
    
    func reloadTransactionsTable() {
        
        self.homeTableView.reloadData()
        self.homeTableView.alpha = 1
        
        if self.visibleTransactions.count == 0 {
            self.setNoTransactionsLabel()
        } else {
            self.noTransactionsLabel.alpha = 0
        }
    }
    
    func setNoTransactionsLabel() {
        
        let textColor = CacheManager.darkModeIsOn() ? "255, 255, 255" : "177, 177, 177"
        
        let noTransactionsHTML = "<center><span style=\"font-family: \'Gilroy-Regular\', \'-apple-system\'; font-size: 16; color: rgb(\(textColor)); line-height: 1.2\">\(Language.getWord(withID: "notransactions1"))</span><span style=\"font-family: \'Gilroy-Bold\', \'-apple-system\'; font-size: 16; color: rgb(\(textColor)); line-height: 1.2\">\(Language.getWord(withID: "buy"))</span><span style=\"font-family: \'Gilroy-Regular\', \'-apple-system\'; font-size: 16; color: rgb(\(textColor)); line-height: 1.2\">\(Language.getWord(withID:"notransactions2"))</span></center>"
        
        if let htmlData = noTransactionsHTML.data(using: .unicode) {
            do {
                let attributedText = try NSAttributedString(data: htmlData, options: [NSAttributedString.DocumentReadingOptionKey.documentType : NSAttributedString.DocumentType.html], documentAttributes: nil)
                self.noTransactionsLabel.attributedText = attributedText
                self.noTransactionsLabel.alpha = 1
            } catch {
                Log.info("Couldn't fetch text: \(error.localizedDescription)")
                SentryManager.capture(error, context: "LoadWalletData row 489")
            }
        }
    }
    
    
    func calculateProfit() {
        
        self.didStartReset = false
        
        // Hide profit label while calculating.
        self.balanceCardGainLabel.alpha = 0
        self.balanceCardProfitView.alpha = 0
        
        // Variables.
        var accumulatedProfit = 0
        var accumulatedInvestments = 0
        var accumulatedCurrentValue = 0
        
        // Get preferred currency.
        let bitcoinValue = BitcoinManager.shared.bittrWallet.getCorrectBitcoinValue()
        
        for eachTransaction in self.visibleTransactions where eachTransaction.isBittr {
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
        
        self.balanceCardGainLabel.text = (accumulatedInvestments == 0) ? "0 %" : "\(Int(((CGFloat(accumulatedProfit)/CGFloat(accumulatedInvestments))*100).rounded())) %".replacingOccurrences(of: "-", with: "")

        // Only reveal the profit once the balance is known.
        self.balanceCardGainLabel.alpha = self.balanceLabel.alpha
        self.balanceCardProfitView.alpha = self.balanceLabel.alpha
        
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
    
    // Warm the price caches ValueVC reads (the historical series + the current
    // value) so opening the Value screen doesn't have to hit the network or flash
    // its loading spinner. Runs at background priority after a short settle delay
    // so it never competes with app startup; no-ops when the caches are still
    // fresh; best-effort — on failure ValueVC just fetches on demand, as before.
    func prefetchPriceData() {
        Task(priority: .background) { [weak self] in
            // Let startup fully settle before touching the network at all.
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard let self else { return }

            let freshCutoff = Calendar.current.date(byAdding: .minute, value: -15, to: Date())!
            let bitcoinValue = BitcoinManager.shared.bittrWallet.getCorrectBitcoinValue()
            let isChf = (bitcoinValue.chosenCurrency == "CHF")

            // Historical series for the currently selected currency.
            let historyFetched = (isChf ? self.chfDataFetched : self.eurDataFetched) ?? .distantPast
            if historyFetched <= freshCutoff,
               let url = URL(string: bitcoinValue.apiUrl),
               let (data, _) = try? await URLSession.shared.data(from: url) {
                await MainActor.run {
                    if isChf { self.chfData = data; self.chfDataFetched = Date() }
                    else { self.eurData = data; self.eurDataFetched = Date() }
                }
            }

            // Current value.
            let currentFetched = self.currentValueFetched ?? .distantPast
            if currentFetched <= freshCutoff,
               let url = URL(string: "https://getbittr.com/api/price/btc"),
               let (data, _) = try? await URLSession.shared.data(from: url) {
                await MainActor.run {
                    self.currentValue = data
                    self.currentValueFetched = Date()
                }
            }
        }
    }

    func finalizeSync() {
        
        // Check if conversion rates have been fetched successfully.
        if self.couldNotFetchConversion {
            self.headerProblemImage.alpha = 1
        }
        
        // Stop sync status spinner.
        self.headerSpinner.stopAnimating()
        self.coreVC!.walletHasSynced = true
        self.coreVC!.completeSync(.final)

        // App is fully ready — warm the Value-screen price caches in the
        // background so opening that screen is instant. Off the startup path.
        self.prefetchPriceData()
        
        // Check if notification needs handling.
        if self.coreVC!.needsToHandleURI() {
            Log.info("Needs to handle URI.")
            self.coreVC!.hideLoading()
            self.coreVC!.checkForPendingURIs()
        } else if let actualNotification = self.coreVC!.lightningNotification {
            Log.info("Needs to handle push notification.")
            // Check if it's a swap notification or payment notification.
            if actualNotification.type == .swap {
                // It's a swap notification.
                self.coreVC!.handleSwapNotificationFromBackground(actualNotification)
            } else if actualNotification.type == .lightningPayout {
                // It's a payout notification.
                self.coreVC!.handlePayoutNotification(actualNotification)
            } else if actualNotification.type == .htlcIncoming {
                self.coreVC!.handleHTLCNotification(actualNotification)
            } else if actualNotification.type == .lnUrl {
                // It's an LNURL notification.
                self.coreVC!.handleLightningAddressNotification(actualNotification)
            }
        } else {
            var userHasBittrAccount = false
            for eachIbanEntity in BitcoinManager.shared.bittrWallet.ibanEntities where eachIbanEntity.yourUniqueCode != "" {
                userHasBittrAccount = true
            }
            // Skip the payout check when a wipe / PIN reset is in progress: the
            // node is about to be torn down, so signing a message against it
            // would race the teardown (force-unwrap of a nil ldkNode).
            if userHasBittrAccount, !self.coreVC!.resettingPin, !self.coreVC!.removingWalletForIncorrectPin {
                Log.info("Check for pending payout.")
                self.coreVC!.checkPendingPayout()
            }
        }
        
        // Check if peer connection has been successful.
        self.fetchAndPrintPeers()
        
        // Check if wallet is being removed from device.
        if (self.coreVC!.resettingPin || self.coreVC!.removingWalletForIncorrectPin), self.coreVC!.genericSpinner.isAnimating {
            self.coreVC!.restoreWalletTapped()
        }
    }

}

extension BalanceDetails {
    func pendingClosureSatoshis(openChannelIds:[ChannelId]) -> Int {
        return self.lightningBalances.forceClosedSatoshis(excludingChannels: openChannelIds)
            + self.pendingBalancesFromChannelClosures.unbroadcastSatoshis()
    }
}

extension [PendingSweepBalance] {
    
    func unbroadcastSatoshis() -> Int {
        
        var totalSatoshis = 0
        for eachBalance in self {
            switch eachBalance {
            case .pendingBroadcast(_, let amountSatoshis): totalSatoshis += Int(amountSatoshis)
            case .broadcastAwaitingConfirmation, .awaitingThresholdConfirmations: break
            }
        }
        return totalSatoshis
    }

    // The transactions carrying the swept funds.
    // A sweep that hasn't been broadcast yet doesn't have one.
    func spendingTxIDs() -> [String] {

        var txIDs = [String]()
        for eachBalance in self {
            switch eachBalance {
            case .broadcastAwaitingConfirmation(_, _, let latestSpendingTxid, _),
                 .awaitingThresholdConfirmations(_, let latestSpendingTxid, _, _, _):
                txIDs += [latestSpendingTxid]
            case .pendingBroadcast: break
            }
        }
        return txIDs
    }
}

extension [LightningBalance] {
    
    func forceClosedSatoshis(excludingChannels openChannelIds:[ChannelId]) -> Int {
        
        var totalSatoshis = 0
        for eachBalance in self {
            switch eachBalance {
            case .claimableAwaitingConfirmations(let channelId, _, let amountSatoshis, _, .holderForceClosed),
                 .claimableAwaitingConfirmations(let channelId, _, let amountSatoshis, _, .counterpartyForceClosed),
                 .claimableAwaitingConfirmations(let channelId, _, let amountSatoshis, _, .htlc),
                 .contentiousClaimable(let channelId, _, let amountSatoshis, _, _, _),
                 .maybeTimeoutClaimableHtlc(let channelId, _, let amountSatoshis, _, _, _),
                 .maybePreimageClaimableHtlc(let channelId, _, let amountSatoshis, _, _),
                 .counterpartyRevokedOutputClaimable(let channelId, _, let amountSatoshis):
                if !openChannelIds.contains(channelId) {
                    totalSatoshis += Int(amountSatoshis)
                }
            case .claimableOnChannelClose,
                 .claimableAwaitingConfirmations(_, _, _, _, .coopClose):
                // Don't include cooperative closes, because those funds already count towards the onchain balance.
                // Matching .coopClose explicitly (rather than a catch-all) keeps this switch exhaustive over
                // BalanceSource, so a future LDK case is a compile error to classify rather than a silent exclusion.
                break
            }
        }
        return totalSatoshis
    }
}
