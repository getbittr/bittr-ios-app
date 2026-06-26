//
//  ProfitViewController.swift
//  bittr
//
//  Created by Tom Melters on 30/04/2023.
//

import UIKit

class ProfitViewController: UIViewController {

    // General
    @IBOutlet weak var subtitleLabel: UILabel!
    @IBOutlet weak var yellowCard: UIView!
    
    // Views
    @IBOutlet weak var investedView: UIView!
    @IBOutlet weak var currentValueView: UIView!
    @IBOutlet weak var profitView: UIView!
    @IBOutlet weak var investedLabel: UILabel!
    @IBOutlet weak var currentLabel: UILabel!
    @IBOutlet weak var profitLabel: UILabel!
    
    // Variables
    var totalProfit = 0
    var totalInvestments = 0
    var totalValue = 0
    var coreVC:CoreViewController?
    
    @IBOutlet weak var totalInvestmentLabel: UILabel!
    @IBOutlet weak var totalValueLabel: UILabel!
    @IBOutlet weak var totalProfitLabel: UILabel!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Corner radii
        self.yellowCard.layer.cornerRadius = 13
        self.investedView.layer.cornerRadius = 8
        self.currentValueView.layer.cornerRadius = 8
        self.profitView.layer.cornerRadius = 8
        self.yellowCard.setShadow()
        
        self.subtitleLabel.accessibilityIdentifier = TestID.Profits.subtitleLabel
        self.totalInvestmentLabel.accessibilityIdentifier = TestID.Profits.totalInvestmentLabel
        self.totalValueLabel.accessibilityIdentifier = TestID.Profits.totalValueLabel
        self.totalProfitLabel.accessibilityIdentifier = TestID.Profits.totalProfitLabel

        let bitcoinValue = self.coreVC!.getCorrectBitcoinValue()

        self.totalInvestmentLabel.text = "\(bitcoinValue.chosenCurrency) \(self.totalInvestments)"
        self.totalValueLabel.text = "\(bitcoinValue.chosenCurrency) \(self.totalValue)"
        self.totalProfitLabel.text = "\(bitcoinValue.chosenCurrency) \(self.totalProfit)"
        
        self.changeColors()
        self.setWords()
        self.addHeader(iconLight: "iconpiggywhite", iconDark: "iconpiggyyellow", title: Language.getWord(withID: "yourprofits"))
    }
    
    func changeColors() {
        
        self.view.backgroundColor = Colors.getColor("yelloworblue1")
        self.subtitleLabel.textColor = Colors.getColor("blackorwhite")
        self.yellowCard.backgroundColor = Colors.getColor("yelloworblue2")
        
        self.totalInvestmentLabel.textColor = Colors.getColor("blackorwhite")
        self.totalValueLabel.textColor = Colors.getColor("blackorwhite")
        self.totalProfitLabel.textColor = Colors.getColor("blackorwhite")
    
        self.investedView.backgroundColor = Colors.getColor("whiteorblue3")
        self.currentValueView.backgroundColor = Colors.getColor("whiteorblue3")
        self.profitView.backgroundColor = Colors.getColor("whiteorblue3")
    }
    
    func setWords() {
        
        self.subtitleLabel.text = Language.getWord(withID: "profitsubtitle")
        self.investedLabel.text = Language.getWord(withID: "totalinvestment")
        self.currentLabel.text = Language.getWord(withID: "currentvalue")
        self.profitLabel.text = Language.getWord(withID: "totalprofit")
        
    }

}
