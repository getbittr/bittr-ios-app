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
        self.visibleTransactions = self.newTransactions
        
        // Finalize sync.
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
    
    func reloadTransactionsTable() {
        
        self.homeTableView.reloadData()
        self.homeTableView.alpha = 1
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
        
        self.didStartReset = false
        self.coreVC!.walletHasSynced = true
        self.coreVC!.completeSync(.final)
        self.reloadTransactionsTable()
        
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
        } else if UserDefaults.standard.bool(forKey: "pendingSwapResume") {
            Log.info("Resuming swap payment from Live Activity tap.")
            self.coreVC!.resumeSwapPayment()
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
