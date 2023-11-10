//
//  ProfitViewController.swift
//  bittr
//
//  Created by Tom Melters on 30/04/2023.
//

import UIKit

class ProfitViewController: UIViewController {

    @IBOutlet weak var downButton: UIButton!
    @IBOutlet weak var headerView: UIView!
    
    @IBOutlet weak var investedView: UIView!
    @IBOutlet weak var divestedView: UIView!
    @IBOutlet weak var currentValueView: UIView!
    @IBOutlet weak var profitView: UIView!
    
    var totalProfit = 0
    var totalInvestments = 0
    var totalValue = 0
    
    @IBOutlet weak var totalInvestmentLabel: UILabel!
    @IBOutlet weak var totalValueLabel: UILabel!
    @IBOutlet weak var totalProfitLabel: UILabel!
    
    override func viewDidLoad() {
        super.viewDidLoad()

        downButton.setTitle("", for: .normal)
        headerView.layer.cornerRadius = 13
        investedView.layer.cornerRadius = 13
        divestedView.layer.cornerRadius = 13
        currentValueView.layer.cornerRadius = 13
        profitView.layer.cornerRadius = 13
        
        var currencySymbol = "€"
        if UserDefaults.standard.value(forKey: "currency") as? String == "CHF" {
            currencySymbol = "CHF"
        }
        
        self.totalInvestmentLabel.text = "\(currencySymbol) \(self.totalInvestments)"
        self.totalValueLabel.text = "\(currencySymbol) \(self.totalValue)"
        self.totalProfitLabel.text = "\(currencySymbol) \(self.totalProfit)"
        
        
    }
    
    @IBAction func downButtonTapped(_ sender: UIButton) {
        self.dismiss(animated: true, completion: nil)
    }

}
