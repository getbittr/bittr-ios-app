//
//  Untitled.swift
//  bittr
//
//  Created by Tom Melters on 07/10/2024.
//

import UIKit

extension HomeViewController {
    
    func setWords() {
        
        self.headerLabel.text = Language.getWord(withID: "syncing")
        self.sendLabel.text = Language.getWord(withID: "send")
        self.receiveLabel.text = Language.getWord(withID: "receive")
        self.buyLabel.text = Language.getWord(withID: "buy")
        self.profitLabel.text = "🌱  " + Language.getWord(withID: "totalprofit")
    }
    
    @objc func changeColors() {
        
        self.headerView.backgroundColor = Colors.getColor(color: "whiteorblue2")
        self.headerLabel.textColor = Colors.getColor(color: "blackorwhite")
        self.headerSpinner.color = Colors.getColor(color: "blackorwhite")
        
        self.sendButtonView.backgroundColor = Colors.getColor(color: "white0.7orblue2")
        self.receiveButtonView.backgroundColor = Colors.getColor(color: "white0.7orblue2")
        self.buyButtonView.backgroundColor = Colors.getColor(color: "white0.7orblue2")
        self.profitButtonView.backgroundColor = Colors.getColor(color: "white0.7orblue2")
        
        self.sendLabel.textColor = Colors.getColor(color: "blackorwhite")
        self.receiveLabel.textColor = Colors.getColor(color: "blackorwhite")
        self.buyLabel.textColor = Colors.getColor(color: "blackorwhite")
        self.profitLabel.textColor = Colors.getColor(color: "blackorwhite")
        self.bittrProfitLabel.textColor = Colors.getColor(color: "blackorwhite")
        
        self.backgroundColorView.backgroundColor = Colors.getColor(color: "yelloworblue3")
        self.backgroundColorTopView.backgroundColor = Colors.getColor(color: "yelloworblue3")
        self.balanceCard.backgroundColor = Colors.getColor(color: "yelloworblue3")
        self.conversionLabel.textColor = Colors.getColor(color: "black0.5orwhite0.5")
        
        self.tableSpinner.color = Colors.getColor(color: "blackorwhite")
        self.bittrProfitSpinner.color = Colors.getColor(color: "blackorwhite")
        self.balanceSpinner.color = Colors.getColor(color: "blackorwhite")
        
        self.satsLabel.textColor = Colors.getColor(color: "blackorwhite")
        
        if CacheManager.darkModeIsOn() {
            self.yellowCurve.image = UIImage(named: "yellowcurvedark")
            self.bitcoinSign.image = UIImage(named: "gilroybitcoinwhite")
        } else {
            self.yellowCurve.image = UIImage(named: "yellowcurve")
            self.bitcoinSign.image = UIImage(named: "gilroybitcoin")
        }
        
        if self.balanceLabel.alpha == 1 {
            self.setTotalSats(updateTableAfterConversion: false)
        }
    }
}
