//
//  ShowCachedData.swift
//  bittr
//
//  Created by Tom Melters on 08/02/2024.
//

import UIKit

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
                    
                    balanceLabelInvisible.text = "B " + (balanceLabel.text?.replacingOccurrences(of: "\n", with: "") ?? "0.00 123 123") + " sats"
                    
                    satsSign.font = balanceLabelInvisible.adjustedFont()
                    
                    satsSign.alpha = 1
                    //questionCircle.alpha = 0.4
                } catch let e as NSError {
                    print("Couldn't fetch text: \(e.localizedDescription)")
                }
            }
        }
        
        // Set cached Eur Value.
        if let cachedEurValue = CacheManager.getCachedData(key: "eurvalue") as? CGFloat {
            self.eurValue = cachedEurValue
        }
        
        // Set cached Chf Value.
        if let cachedChfValue = CacheManager.getCachedData(key: "chfvalue") as? CGFloat {
            self.chfValue = cachedChfValue
        }
        
        // Set cached transactions.
        if let cachedTransactions = CacheManager.getCachedData(key: "transactions") as? [Transaction] {
            
            self.setTransactions = cachedTransactions
            self.newTransactions = cachedTransactions
            self.lastCachedTransactions = cachedTransactions
        }
        
        // Set conversion.
        if let actualCachedBalance = CacheManager.getCachedData(key: "satsbalance") as? String {
                
            self.bittrTransactions = NSMutableDictionary()
            for eachTransaction in self.lastCachedTransactions {
                if eachTransaction.isBittr == true {
                    self.bittrTransactions.setValue(["amount":"\(eachTransaction.purchaseAmount)", "currency":eachTransaction.currency], forKey: eachTransaction.id)
                }
            }
            
            self.setConversion(btcValue: CGFloat(truncating: NumberFormatter().number(from: actualCachedBalance)!)/100000000, cachedData: true)
        }
    }

}
