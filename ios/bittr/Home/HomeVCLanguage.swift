//
//  Untitled.swift
//  bittr
//
//  Created by Tom Melters on 07/10/2024.
//

import UIKit

extension HomeViewController {
    
    @objc func setWords() {
        
        self.headerLabel.text = Language.getWord(withID: "yourwallet")
        self.sendLabel.text = Language.getWord(withID: "send")
        self.receiveLabel.text = Language.getWord(withID: "receive")
        self.buyLabel.text = Language.getWord(withID: "buy")
    }
    
    @objc func changeColors() {
        
        //self.headerView.backgroundColor = Colors.getColor("whiteorblue3")
        self.headerLabel.textColor = Colors.getColor("whiteoryellow")
        self.headerSpinner.color = Colors.getColor("whiteoryellow")
        
        self.sendButtonView.backgroundColor = Colors.getColor("white0.7orblue2")
        self.receiveButtonView.backgroundColor = Colors.getColor("white0.7orblue2")
        self.buyButtonView.backgroundColor = Colors.getColor("white0.7orblue2")
        
        self.sendLabel.textColor = Colors.getColor("blackorwhite")
        self.receiveLabel.textColor = Colors.getColor("blackorwhite")
        self.buyLabel.textColor = Colors.getColor("blackorwhite")
        
        if self.balanceCardArrowImage.image == UIImage(systemName: "arrow.down") {
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
        
        self.backgroundColorView.backgroundColor = Colors.getColor("yelloworblue3")
        self.backgroundColorTopView.backgroundColor = Colors.getColor("yelloworblue3")
        self.bottomCurve.fillColor = Colors.getColor("yelloworblue3")
        self.balanceCard.backgroundColor = Colors.getColor("yelloworblue3")
        
        if CacheManager.darkModeIsOn() {
            self.bitcoinSign.image = UIImage(named: "gilroybitcoinwhite")
            self.headerPiggyImage.image = UIImage(named: "iconpiggyyellow")
            self.headerDetailsImage.image = UIImage(named: "icondetailsyellow")
            self.headerCurrencyImage.image = UIImage(named: "iconexchangeyellow")
            self.headerMapImage.image = UIImage(named: "iconmapyellow")
            self.conversionLabel.textColor = UIColor(red: 170/255, green: 190/255, blue: 217/255, alpha: 1)
        } else {
            self.bitcoinSign.image = UIImage(named: "gilroybitcoin")
            self.headerPiggyImage.image = UIImage(named: "iconpiggywhite")
            self.headerDetailsImage.image = UIImage(named: "icondetailswhite")
            self.headerCurrencyImage.image = UIImage(named: "iconexchange")
            self.headerMapImage.image = UIImage(named: "iconmapwhite")
            self.conversionLabel.textColor = UIColor(red: 201/255, green: 154/255, blue: 0/255, alpha: 1)
        }
        
        if self.balanceLabel.alpha == 1 {
            if let actualCachedBalance = CacheManager.getCachedData(key: "satsbalance") as? String {
                self.loadBalanceLabel(amount: actualCachedBalance)
                self.setConversion()
                
                // Update table.
                self.reloadTransactionsTable()
                self.calculateProfit()
            }
        }
        
        if self.noTransactionsLabel.alpha == 1 {
            self.setNoTransactionsLabel()
        }
    }
    
    func setBasicStyling() {
        
        // Corner radii
        self.buyButtonView.layer.cornerRadius = 8
        self.sendButtonView.layer.cornerRadius = 8
        self.receiveButtonView.layer.cornerRadius = 8
        self.headerView.layer.cornerRadius = 13
        self.balanceCard.layer.cornerRadius = 13
        self.balanceCardProfitView.layer.cornerRadius = 13
        
        // Button titles
        self.profitButton.setTitle("", for: .normal)
        self.buyButton.setTitle("", for: .normal)
        self.sendButton.setTitle("", for: .normal)
        self.receiveButton.setTitle("", for: .normal)
        self.balanceCardButton.setTitle("", for: .normal)
        self.headerViewButton.setTitle("", for: .normal)
        self.currencyButton.setTitle("", for: .normal)
        self.mapButton.setTitle("", for: .normal)
        
        // Balance card shadow
        self.balanceCard.setShadow()
        self.sendButtonView.setShadow()
        self.receiveButtonView.setShadow()
        self.buyButtonView.setShadow()
    }
}
