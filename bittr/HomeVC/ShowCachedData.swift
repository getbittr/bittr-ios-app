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
            if cachedBalance != "empty" {
                
                if let htmlData = cachedBalance.data(using: .unicode) {
                    do {
                        let attributedText = try NSAttributedString(data: htmlData, options: [NSAttributedString.DocumentReadingOptionKey.documentType : NSAttributedString.DocumentType.html], documentAttributes: nil)
                        balanceLabel.attributedText = attributedText
                        balanceLabel.alpha = 1
                        bitcoinSign.alpha = 0.22
                        satsSign.alpha = 1
                        questionCircle.alpha = 0.4
                    } catch let e as NSError {
                        print("Couldn't fetch text: \(e.localizedDescription)")
                    }
                }
            }
        }
        
        // Set cached conversion.
        /*if let cachedConversion = CacheManager.getCachedData(key: "conversion") as? String {
            if cachedConversion != "empty" {
                
                self.conversionLabel.text = cachedConversion
                self.balanceSpinner.stopAnimating()
                self.conversionLabel.alpha = 1
            }
        }*/
        
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
            
            /*self.homeTableView.reloadData()
            self.tableSpinner.stopAnimating()
            self.homeTableView.alpha = 1
            self.homeTableView.isUserInteractionEnabled = false*/
        }
        
        // Set conversion.
        if let actualCachedBalance = CacheManager.getCachedData(key: "satsbalance") as? String {
            if actualCachedBalance != "empty" {
                
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

}
