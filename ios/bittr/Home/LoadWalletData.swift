//
//  LoadWalletData.swift
//  bittr
//
//  Created by Tom Melters on 08/02/2024.
//

import UIKit
import LDKNode
import Sentry

extension HomeViewController {

    func loadWalletData() {
        
        // Get channels, balance, and funding transaction ID.
        BitcoinManager.shared.bittrWallet.satoshisLightning = 0
        BitcoinManager.shared.bittrWallet.lightningChannels = BitcoinManager.shared.listChannels()
        if let activeChannel = BitcoinManager.shared.bittrWallet.lightningChannels.getActiveChannel() {
            if let channelTxoID = activeChannel.fundingTxo?.txid as? String {
                CacheManager.storeTxoID(txoID: channelTxoID)
            }
            if Int(activeChannel.outboundCapacityMsat/1000) != 0 {
                // Channel balance is more than punishment reserve.
                BitcoinManager.shared.bittrWallet.satoshisLightning += Int((activeChannel.outboundCapacityMsat / 1000) + (activeChannel.unspendablePunishmentReserve ?? 0))
            } else {
                // Channel balance is less than punishment reserve.
                BitcoinManager.shared.bittrWallet.satoshisLightning += Int(activeChannel.channelValueSats - activeChannel.inboundCapacityMsat/1000 - activeChannel.counterpartyUnspendablePunishmentReserve)
            }
        }
        
        // Get transactions.
        BitcoinManager.shared.bittrWallet.allTransactions = BitcoinManager.shared.listPayments()
        
        // Get onchain balance.
        BitcoinManager.shared.bittrWallet.satoshisOnchain = Int(BitcoinManager.shared.ldkNode!.listBalances().totalOnchainBalanceSats)
        
        Task {
            // Check whether transactions were Bittr purchases.
            _ = await self.getBittrTransactionDetails()
            
            DispatchQueue.main.async {
                self.updateTransactionHistory()
            }
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
            if !self.cachedLightningIds.contains(eachPayment.kind.transactionID ?? eachPayment.id), (eachPayment.status == .succeeded || (eachPayment.status == .pending && eachPayment.direction == .outbound && (Int((eachPayment.amountMsat ?? 0)/1000) > 0 || Int((eachPayment.feePaidMsat ?? 0)/1000) > 0)) || (eachPayment.status == .pending && eachPayment.kind.isOnchain && eachPayment.direction == .inbound)) {
                
                // Create transaction.
                let thisTransaction = eachPayment.createTransaction(coreVC: self.coreVC, bittrTransactions: self.bittrTransactions)
                self.newTransactions += [thisTransaction]
                
                // Cache succeeded Lightning payments.
                if thisTransaction.isLightning, eachPayment.status == .succeeded {
                    CacheManager.storeLightningTransaction(thisTransaction: thisTransaction)
                }
            }
            
            // Make sure there are no duplicate transactions.
            if eachPayment.kind.transactionID != nil {
                if self.cachedLightningIds.contains(eachPayment.kind.transactionID!), self.cachedLightningIds.contains(eachPayment.id) {
                    for (index, eachTransaction) in self.newTransactions.enumerated().reversed() {
                        if eachTransaction.id == eachPayment.id {
                            self.newTransactions.remove(at: index)
                        }
                    }
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
        CacheManager.updateCachedData(data: self.newTransactions, key: "transactions")
        
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
        for eachTransaction in (CacheManager.getCachedData(key: "transactions") as? [Transaction]) ?? [Transaction]() where eachTransaction.isBittr {
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
            DispatchQueue.main.async {
                SentrySDK.capture(error: error) { scope in
                    scope.setExtra(value: "LoadWalletData row 266", key: "context")
                }
            }
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
                let thisTransaction = eachTransaction.createTransaction(coreVC: self.coreVC, isFundingTransaction: true)
                self.newTransactions += [thisTransaction]
                CacheManager.storeLightningTransaction(thisTransaction: thisTransaction)
            }
        }
        
        return true
    }
    
    
    func setTotalSats() {
        // Calculate total balance
        let totalBalanceSats = BitcoinManager.shared.bittrWallet.satoshisOnchain + BitcoinManager.shared.bittrWallet.satoshisLightning
        let totalBalanceSatsString = "\(totalBalanceSats)"
        
        // Load balance label.
        self.loadBalanceLabel(amount: totalBalanceSatsString)
        
        // Convert balance to EUR / CHF.
        self.setConversion()
    }
    
    func loadBalanceLabel(amount:String) {
        
        // Update bitcoin sign alpha.
        var bitcoinSignAlpha = CacheManager.darkModeIsOn() ? 0.47 : 0.18
        
        // Create balance representation with bold satoshis.
        let allZeros = ["", "0.00 000 00", "0.00 000 0", "0.00 000 ", "0.00 00", "0.00 0", "0.00 ", "0.0", "0."]
        var zeros = ""
        var numbers = amount.addSpaces()
        var sats = "  sats"
        
        if amount.count < 9 {
            zeros = allZeros[amount.count]
        } else {
            numbers = "\(amount.toNumber().inBTC())".replacingOccurrences(of: ",", with: ".")
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
            sats = ""
        }
        
        // Set text to invisible label to calculate font size for HTML text.
        self.balanceLabelInvisible.text = "B " + zeros + numbers + " sats"
        let font = self.balanceLabelInvisible.adjustedFont()
        let adjustedSize = Int(font.pointSize)
        
        // Set HTML balance text.
        let transparentColor = CacheManager.darkModeIsOn() ? "170, 190, 217" : "201, 154, 0"
        let fillColor = CacheManager.darkModeIsOn() ? "255, 255, 255" : "0, 0, 0"
        self.balanceText = "<center><span style=\"font-family: \'Gilroy-Bold\', \'-apple-system\'; font-size: \(adjustedSize); color: rgb(\(transparentColor)); line-height: 0.5\">\(zeros)</span><span style=\"font-family: \'Gilroy-Bold\', \'-apple-system\'; font-size: \(adjustedSize); color: rgb(\(fillColor)); line-height: 0.5\">\(numbers)\(sats)</span></center>"
        
        guard let htmlData = self.balanceText.data(using: .unicode) else { return }
        
        let attributedText:NSAttributedString
        do {
            attributedText = try NSAttributedString(data: htmlData, options: [NSAttributedString.DocumentReadingOptionKey.documentType : NSAttributedString.DocumentType.html], documentAttributes: nil)
        } catch {
            Log.info("Couldn't fetch text: \(error.localizedDescription)")
            DispatchQueue.main.async {
                SentrySDK.capture(error: error) { scope in
                    scope.setExtra(value: "LoadWalletData row 360", key: "context")
                }
            }
            return
        }
        
        self.balanceLabel.attributedText = attributedText
        self.balanceLabel.alpha = 1
        self.bitcoinSign.alpha = bitcoinSignAlpha
        
        // Store satoshis balance string to cache.
        CacheManager.updateCachedData(data: amount, key: "satsbalance")
    }
    
    
    func setConversion() {
        
        // Set, cache, and show conversion label.
        let cachedBtcBalance = (CacheManager.getCachedData(key: "satsbalance") as? String ?? "0").toNumber().inBTC()
        let conversionLabelText = self.updateConversionLabel(btcValue: cachedBtcBalance)
        CacheManager.updateCachedData(data: conversionLabelText, key: "conversion")
        
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
            DispatchQueue.main.async {
                SentrySDK.capture(error: error) { scope in
                    scope.setExtra(value: "LoadWalletData row 394", key: "context")
                }
            }
            Log.info("Could not download conversion rates.")
            return false
        }
        
        guard
            let actualEurValue = receivedDictionary["btc_eur"] as? String,
            let actualChfValue = receivedDictionary["btc_chf"] as? String
        else {
            Log.info("Could not download conversion rates.")
            SentrySDK.capture(message: "Received unexpected data from conversion API.")
            return false
        }
            
        // Set updated conversion rates for EUR and CHF.
        BitcoinManager.shared.bittrWallet.valueInEUR = actualEurValue.fixDecimals().toNumber()
        BitcoinManager.shared.bittrWallet.valueInCHF = actualChfValue.fixDecimals().toNumber()
        
        // Store updated conversion rates in cache.
        CacheManager.updateCachedData(data: BitcoinManager.shared.bittrWallet.valueInEUR ?? 0.0, key: "eurvalue")
        CacheManager.updateCachedData(data: BitcoinManager.shared.bittrWallet.valueInCHF ?? 0.0, key: "chfvalue")
        
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
                DispatchQueue.main.async {
                    SentrySDK.capture(error: error) { scope in
                        scope.setExtra(value: "LoadWalletData row 489", key: "context")
                    }
                }
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

            let transactionCurrency:String = {
                if eachTransaction.currency == "EUR" {
                    return "€"
                } else {
                    return "CHF"
                }
            }()
            if transactionCurrency != bitcoinValue.chosenCurrency {
                if transactionCurrency == "€" {
                    correctConversion = BitcoinManager.shared.bittrWallet.valueInEUR ?? 0
                } else {
                    correctConversion = BitcoinManager.shared.bittrWallet.valueInCHF ?? 0
                }
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
        
        if accumulatedInvestments != 0 {
            self.balanceCardGainLabel.text = "\(Int(((CGFloat(accumulatedProfit)/CGFloat(accumulatedInvestments))*100).rounded())) %".replacingOccurrences(of: "-", with: "")
        } else {
            self.balanceCardGainLabel.text = "0 %"
        }

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
    
    func finalizeSync() {
        
        // Check if conversion rates have been fetched successfully.
        if self.couldNotFetchConversion {
            self.headerProblemImage.alpha = 1
        }
        
        // Stop sync status spinner.
        self.headerSpinner.stopAnimating()
        self.coreVC!.walletHasSynced = true
        self.coreVC!.completeSync(.final)
        
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
            for eachIbanEntity in BitcoinManager.shared.bittrWallet.ibanEntities {
                if eachIbanEntity.yourUniqueCode != "" {
                    userHasBittrAccount = true
                }
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
    var transactionID: String? {
        switch self {
        case .onchain(let txID, _):
            return txID
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
    
    var isOnchain: Bool {
        switch self {
        case .onchain(_, _):
            return true
        default:
            return false
        }
    }
}

extension [Transaction] {
    
    func performSwapMatching() -> [Transaction] {
        
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
                Log.info("Found completed swap.")
                print("Swap ID: \(eachSwapID)")
                
                let thisSwapID = (eachSwapID as! String)
                let firstTransaction = (eachSetOfTransactions as! [Transaction])[0]
                let secondTransaction = (eachSetOfTransactions as! [Transaction])[1]
                
                if thisSwapID.contains(firstTransaction.id), firstTransaction.swapStatus == .succeeded {
                    // This is already a completed Swap transaction.
                    for (index, eachTransaction) in currentTransactions.enumerated().reversed() {
                        if secondTransaction.id == eachTransaction.id {
                            currentTransactions.remove(at: index)
                        }
                    }
                    CacheManager.storeLightningTransaction(thisTransaction: firstTransaction)
                } else if thisSwapID.contains(secondTransaction.id), secondTransaction.swapStatus == .succeeded {
                    // This is already a completed Swap transaction.
                    for (index, eachTransaction) in currentTransactions.enumerated().reversed() {
                        if firstTransaction.id == eachTransaction.id {
                            currentTransactions.remove(at: index)
                        }
                    }
                    CacheManager.storeLightningTransaction(thisTransaction: secondTransaction)
                } else {
                    
                    let swapTransaction = Transaction()
                    swapTransaction.isSwap = true
                    swapTransaction.boltzSwapId = CacheManager.getSwapID(dateID: thisSwapID) ?? "Unavailable"
                    swapTransaction.lnDescription = thisSwapID

                    swapTransaction.sent = firstTransaction.received + secondTransaction.received - firstTransaction.sent - secondTransaction.sent

                    // Per-leg fees live on Transaction.fee (onchain network fee for
                    // the onchain leg, lightning routing fee for an outbound
                    // lightning leg). The home row renders cost as
                    // (received - sent - fee), so without this the user-paid fee
                    // on either side gets dropped from the displayed swap cost.
                    // Inbound legs have fee = 0, so summing both is safe.
                    swapTransaction.fee = firstTransaction.fee + secondTransaction.fee
                    
                    if thisSwapID.contains("onchain to lightning") {
                        swapTransaction.swapDirection = .onchainToLightning
                        swapTransaction.isLightning = false
                        swapTransaction.id = thisSwapID.replacingOccurrences(of: "Swap onchain to lightning ", with: "")
                    } else {
                        swapTransaction.swapDirection = .lightningToOnchain
                        swapTransaction.isLightning = true
                        swapTransaction.id = thisSwapID.replacingOccurrences(of: "Swap lightning to onchain ", with: "")
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
                            if swapTransaction.swapDirection == .lightningToOnchain {
                                swapTransaction.timestamp = eachTransaction.timestamp
                                swapTransaction.received = eachTransaction.received - eachTransaction.sent
                            } else {
                                swapTransaction.sent = eachTransaction.sent - eachTransaction.received
                            }
                        }
                    }
                    
                    if !firstTransaction.isLightning, !secondTransaction.isLightning {
                        // Both transactions are onchain. This is a failed normal swap.
                        swapTransaction.timestamp = firstTransaction.timestamp
                        swapTransaction.sent = firstTransaction.sent + secondTransaction.sent
                        swapTransaction.received = firstTransaction.received + secondTransaction.received
                        swapTransaction.swapStatus = .failed
                        
                        if (firstTransaction.received - firstTransaction.sent) < (secondTransaction.received - secondTransaction.sent) {
                            // The 2nd transaction is the refund.
                            swapTransaction.onchainID = firstTransaction.id
                            swapTransaction.lightningID = secondTransaction.id
                        } else {
                            // The 1st transaction is the refund.
                            swapTransaction.onchainID = secondTransaction.id
                            swapTransaction.lightningID = firstTransaction.id
                        }
                    }
                    
                    // Remove the individual transactions and add the combined swap transaction
                    let transactionIDs = [firstTransaction.id, secondTransaction.id]
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
                Log.info("Found pending swap.")
                print("Swap ID: \(eachSwapID)")
                
                let thisTransaction = (eachSetOfTransactions as! [Transaction])[0]
                let thisSwapID = (eachSwapID as! String)
                
                if let suggestedSwapStatus = CacheManager.getSuggestedSwapStatus(dateID: thisSwapID) {
                    thisTransaction.isSuggestedSwap = true
                    thisTransaction.swapStatus = suggestedSwapStatus
                    if thisSwapID.contains("onchain to lightning") {
                        thisTransaction.swapDirection = .onchainToLightning
                    } else {
                        thisTransaction.swapDirection = .lightningToOnchain
                    }
                    thisTransaction.boltzSwapId = CacheManager.getSwapID(dateID: thisSwapID) ?? "Unavailable"
                    continue
                }
                
                let swapTransaction = Transaction()
                swapTransaction.isSwap = true
                swapTransaction.swapStatus = .pending
                swapTransaction.boltzSwapId = CacheManager.getSwapID(dateID: thisSwapID) ?? "Unavailable"
                swapTransaction.lnDescription = thisSwapID
                
                swapTransaction.timestamp = thisTransaction.timestamp
                swapTransaction.sent = thisTransaction.sent
                swapTransaction.received = thisTransaction.received
                swapTransaction.isLightning = thisTransaction.isLightning
                swapTransaction.id = thisSwapID.replacingOccurrences(of: "Swap lightning to onchain ", with: "").replacingOccurrences(of: "Swap onchain to lightning ", with: "")
                
                if thisSwapID.contains("onchain to lightning") {
                    swapTransaction.swapDirection = .onchainToLightning
                } else {
                    swapTransaction.swapDirection = .lightningToOnchain
                }
                
                if swapTransaction.isLightning {
                    swapTransaction.lightningID = thisTransaction.id
                    swapTransaction.channelId = thisTransaction.channelId
                } else {
                    swapTransaction.onchainID = thisTransaction.id
                    swapTransaction.height = thisTransaction.height
                }
                
                // Remove the individual transactions and add the combined swap transaction
                for (index, eachTransaction) in currentTransactions.enumerated().reversed() {
                    if eachTransaction.id == thisTransaction.id {
                        currentTransactions.remove(at: index)
                    }
                }
                
                currentTransactions += [swapTransaction]
            }
        }
        
        return currentTransactions
    }
}
