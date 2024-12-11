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
        self.profitLabel.text = "🌱  " + Language.getWord(withID: "totalprofit")
    }
    
    @objc func changeColors() {
        
        //self.headerView.backgroundColor = Colors.getColor("whiteorblue3")
        self.headerLabel.textColor = Colors.getColor("whiteoryellow")
        self.headerSpinner.color = Colors.getColor("whiteoryellow")
        
        self.sendButtonView.backgroundColor = Colors.getColor("white0.7orblue2")
        self.receiveButtonView.backgroundColor = Colors.getColor("white0.7orblue2")
        self.buyButtonView.backgroundColor = Colors.getColor("white0.7orblue2")
        self.profitButtonView.backgroundColor = Colors.getColor("white0.7orblue2")
        
        self.sendLabel.textColor = Colors.getColor("blackorwhite")
        self.receiveLabel.textColor = Colors.getColor("blackorwhite")
        self.buyLabel.textColor = Colors.getColor("blackorwhite")
        self.profitLabel.textColor = Colors.getColor("blackorwhite")
        self.bittrProfitLabel.textColor = Colors.getColor("blackorwhite")
        
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
        self.balanceCard.backgroundColor = Colors.getColor("yelloworblue2")
        self.conversionLabel.textColor = Colors.getColor("black0.5orwhite0.5")
        
        self.tableSpinner.color = Colors.getColor("blackorwhite")
        self.bittrProfitSpinner.color = Colors.getColor("blackorwhite")
        self.balanceSpinner.color = Colors.getColor("blackorwhite")
        
        self.satsLabel.textColor = Colors.getColor("blackorwhite")
        
        if CacheManager.darkModeIsOn() {
            self.yellowCurve.image = UIImage(named: "yellowcurvedark")
            self.bitcoinSign.image = UIImage(named: "gilroybitcoinwhite")
            self.headerPiggyImage.image = UIImage(named: "iconpiggyyellow")
            self.headerDetailsImage.image = UIImage(named: "icondetailsyellow")
        } else {
            self.yellowCurve.image = UIImage(named: "yellowcurve")
            self.bitcoinSign.image = UIImage(named: "gilroybitcoin")
            self.headerPiggyImage.image = UIImage(named: "iconpiggywhite")
            self.headerDetailsImage.image = UIImage(named: "icondetailswhite")
        }
        
        if self.balanceLabel.alpha == 1 {
            self.setTotalSats(updateTableAfterConversion: false)
        }
    }
}
