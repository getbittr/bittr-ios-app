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
        
        // Set cached transactions.
        if let cachedTransactions = CacheManager.getCachedData(key: "transactions") as? [Transaction] {
            
            self.visibleTransactions = cachedTransactions
            self.newTransactions = cachedTransactions
            
            self.bittrTransactions.removeAllObjects()
            for eachTransaction in self.visibleTransactions {
                if eachTransaction.isBittr {
                    self.bittrTransactions.setValue(["amount":"\(eachTransaction.purchaseAmount)", "currency":eachTransaction.currency], forKey: eachTransaction.id)
                }
            }
        }
        
        // Set conversion.
        if let actualCachedBalance = CacheManager.getCachedData(key: "satsbalance") as? String {
            
            self.loadBalanceLabel(amount: actualCachedBalance)
            
            self.setConversion(btcValue: actualCachedBalance.toNumber().inBTC(), cachedData: true, updateTableAfterConversion: true)
        }
    }

}
