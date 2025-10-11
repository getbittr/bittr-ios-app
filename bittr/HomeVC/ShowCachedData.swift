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
        
        // Set cached balance.
        if let cachedBalance = CacheManager.getCachedData(key: "balance") as? String {
                
            if let htmlData = cachedBalance.data(using: .unicode) {
                do {
                    let attributedText = try NSAttributedString(data: htmlData, options: [NSAttributedString.DocumentReadingOptionKey.documentType : NSAttributedString.DocumentType.html], documentAttributes: nil)
                    balanceLabel.attributedText = attributedText
                    balanceLabel.alpha = 1
                    bitcoinSign.alpha = 0.18
                    if CacheManager.darkModeIsOn() {
                        bitcoinSign.alpha = 0.35
                    }
                    
                    self.balanceLabelInvisible.text = "B " + (balanceLabel.text?.replacingOccurrences(of: "\n", with: "") ?? "0.00 123 123") + " sats"
                    
                    satsLabel.font = self.balanceLabelInvisible.adjustedFont()
                    
                    satsLabel.alpha = 1
                } catch {
                    print("Couldn't fetch text: \(error.localizedDescription)")
                    DispatchQueue.main.async {
                        SentrySDK.capture(error: error) { scope in
                            scope.setExtra(value: "ShowCachedData row 38", key: "context")
                        }
                    }
                }
            }
        }
        
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
            
            self.setTransactions = cachedTransactions
            self.newTransactions = cachedTransactions
            self.lastCachedTransactions = cachedTransactions
            
            self.bittrTransactions.removeAllObjects()
            for eachTransaction in self.lastCachedTransactions {
                if eachTransaction.isBittr {
                    self.bittrTransactions.setValue(["amount":"\(eachTransaction.purchaseAmount)", "currency":eachTransaction.currency], forKey: eachTransaction.id)
                }
            }
        }
        
        // Set conversion.
        if let actualCachedBalance = CacheManager.getCachedData(key: "satsbalance") as? String {
            
            self.setConversion(btcValue: actualCachedBalance.toNumber().inBTC(), cachedData: true, updateTableAfterConversion: true)
        }
    }

}
