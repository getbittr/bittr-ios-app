//
//  ShowCachedData.swift
//  bittr
//
//  Created by Tom Melters on 08/02/2024.
//

import UIKit
import Sentry

extension HomeViewController {

    func showCachedData() {
        
        // Set cached Eur Value.
        if let cachedEurValue = CacheManager.getCachedData(key: "eurvalue") as? CGFloat {
            self.coreVC?.bittrWallet.valueInEUR = cachedEurValue
        }
        
        // Set cached Chf Value.
        if let cachedChfValue = CacheManager.getCachedData(key: "chfvalue") as? CGFloat {
            self.coreVC?.bittrWallet.valueInCHF = cachedChfValue
        }
        
        // Set conversion.
        if let actualCachedBalance = CacheManager.getCachedData(key: "satsbalance") as? String {
            
            // Show cached balance.
            self.loadBalanceLabel(amount: actualCachedBalance)
            
            // Set conversion label.
            self.setConversion()
        }
        
        // Set cached transactions.
        if let cachedTransactions = CacheManager.getCachedData(key: "transactions") as? [Transaction] {
            
            self.visibleTransactions = cachedTransactions
            self.newTransactions = cachedTransactions
            
            self.bittrTransactions.removeAllObjects()
            for eachTransaction in self.visibleTransactions {
                if eachTransaction.isBittr {
                    self.bittrTransactions.setValue(["fiatNetAmount":eachTransaction.fiatNetAmount, "fiatGrossAmount":eachTransaction.fiatGrossAmount, "currency":eachTransaction.currency, "transferFee":eachTransaction.transferFee, "surcharge":eachTransaction.surcharge, "bittrFee":eachTransaction.bittrFee], forKey: eachTransaction.id)
                }
            }
            
            // Reload table.
            self.reloadTransactionsTable()
            
            // Calculate profits.
            self.calculateProfit()
        }
    }
    
    func downloadConversionAndBlockHeight() {
        
        Task {
            // Download conversion rates.
            self.coreVC?.startSync(.conversion)
            self.didFetchConversion = await self.didFetchConversionRates()
            if !self.didFetchConversion {
                self.couldNotFetchConversion = true
            } else {
                self.coreVC?.completeSync(.conversion)
            }
            
            // Download current block height.
            if BitcoinManager.shared.coreVC == nil {
                BitcoinManager.shared.coreVC = self.coreVC!
            }
            _ = await BitcoinManager.shared.didGetLatestBlockHeight()
            
            DispatchQueue.main.async {
                // Update conversion label.
                self.setConversion()
                
                // Update table.
                self.reloadTransactionsTable()
                
                // Calculate profits.
                self.calculateProfit()
            }
        }
    }

}
