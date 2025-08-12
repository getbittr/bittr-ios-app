//
//  ProfitViewController.swift
//  bittr
//
//  Created by Tom Melters on 30/04/2023.
//

import UIKit

class ProfitViewController: UIViewController {

    // General
    @IBOutlet weak var downButton: UIButton!
    @IBOutlet weak var headerLabel: UILabel!
    @IBOutlet weak var subtitleLabel: UILabel!
    
    // Views
    @IBOutlet weak var investedView: UIView!
    @IBOutlet weak var divestedView: UIView!
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

        self.downButton.setTitle("", for: .normal)
        self.investedView.layer.cornerRadius = 13
        self.divestedView.layer.cornerRadius = 13
        self.currentValueView.layer.cornerRadius = 13
        self.profitView.layer.cornerRadius = 13
        
        let bitcoinValue = self.getCorrectBitcoinValue(coreVC: self.coreVC!)
        
        self.totalInvestmentLabel.text = "\(bitcoinValue.chosenCurrency) \(self.totalInvestments)"
        self.totalValueLabel.text = "\(bitcoinValue.chosenCurrency) \(self.totalValue)"
        self.totalProfitLabel.text = "\(bitcoinValue.chosenCurrency) \(self.totalProfit)"
        
        self.changeColors()
        self.setWords()
    }
    
    @IBAction func downButtonTapped(_ sender: UIButton) {
        self.dismiss(animated: true, completion: nil)
    }
    
    func changeColors() {
        
        self.view.backgroundColor = Colors.getColor("yelloworblue1")
        self.subtitleLabel.textColor = Colors.getColor("blackorwhite")
        
        self.totalInvestmentLabel.textColor = Colors.getColor("blackorwhite")
        self.totalValueLabel.textColor = Colors.getColor("blackorwhite")
        self.totalProfitLabel.textColor = Colors.getColor("blackorwhite")
        
        self.investedLabel.textColor = Colors.getColor("blackoryellow")
        self.currentLabel.textColor = Colors.getColor("blackoryellow")
        self.profitLabel.textColor = Colors.getColor("blackoryellow")
    
        self.investedView.backgroundColor = Colors.getColor("white0.7orblue2")
        self.currentValueView.backgroundColor = Colors.getColor("white0.7orblue2")
        self.profitView.backgroundColor = Colors.getColor("white0.7orblue2")
    }
    
    func setWords() {
        
        self.headerLabel.text = Language.getWord(withID: "yourprofits")
        self.subtitleLabel.text = Language.getWord(withID: "profitsubtitle")
        self.investedLabel.text = "⬇️  " + Language.getWord(withID: "totalinvestment")
        self.currentLabel.text = "💰  " + Language.getWord(withID: "currentvalue")
        self.profitLabel.text = "🌱  " + Language.getWord(withID: "totalprofit")
        
    }

}
