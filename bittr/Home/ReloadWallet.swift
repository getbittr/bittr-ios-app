//
//  ReloadWallet.swift
//  bittr
//
//  Created by Tom Melters on 2/27/26.
//

import UIKit

extension HomeViewController {
    
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        if scrollView.contentOffset.y < -200, !self.didStartReset, !self.headerSpinner.isAnimating {
            Log.info("Reload wallet when pulling down the view.")
            
            guard self.coreVC!.checkInternetConnection() else { return }
            
            self.resetWallet()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                // Perform reset.
                Task {
                    await self.coreVC!.startWallet()
                }
            }
        } else if scrollView.contentOffset.y > 400 {
            self.coreVC?.yearView.alpha = 1
        } else {
            self.coreVC?.yearView.alpha = 0
        }
    }
    
    func resetWallet() {
        Log.info("Reset wallet.")
        self.didStartReset = true
        
        self.visibleTransactions.removeAll()
        self.newTransactions.removeAll()
        self.calculatedProfit = 0
        self.calculatedInvestments = 0
        self.calculatedCurrentValue = 0
        self.coreVC?.bittrWallet.satoshisOnchain = 0
        self.coreVC?.bittrWallet.satoshisLightning = 0
        
        self.noTransactionsLabel.alpha = 0
        self.balanceCardProfitView.alpha = 0
        self.balanceCardGainLabel.alpha = 0
        self.balanceLabel.alpha = 0
        self.bitcoinSign.alpha = 0
        self.conversionLabel.alpha = 0
        self.homeTableView.reloadData()
        
        self.headerSpinner.startAnimating()
        self.headerProblemImage.alpha = 0
        self.couldNotFetchConversion = false
        self.didFetchConversion = false
        self.coreVC?.walletHasSynced = false
        
        if self.coreVC!.walletSync != nil {
            self.coreVC!.walletSync!.stop()
            self.coreVC!.walletSync = nil
        }
    }
}
