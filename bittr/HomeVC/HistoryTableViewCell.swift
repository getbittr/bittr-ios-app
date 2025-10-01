//
//  HistoryTableViewCell.swift
//  bittr
//
//  Created by Tom Melters on 18/04/2023.
//

import UIKit

class HistoryTableViewCell: UITableViewCell {

    // Date
    @IBOutlet weak var dateView: UIView!
    @IBOutlet weak var dayLabel: UILabel!
    
    // Value
    @IBOutlet weak var satsLabel: UILabel!
    @IBOutlet weak var eurosLabel: UILabel!
    
    // Card and button
    @IBOutlet weak var transactionButton: UIButton!
    @IBOutlet weak var cardView: UIView!
    
    // Bittr stack
    @IBOutlet weak var bittrStack: UIView!
    @IBOutlet weak var bittrStackWidth: NSLayoutConstraint!
    @IBOutlet weak var gainView: UIView!
    @IBOutlet weak var gainLabel: UILabel!
    @IBOutlet weak var arrowImage: UIImageView!
    @IBOutlet weak var bittrImage: UIImageView!
    
    // Lightning stack
    @IBOutlet weak var lightningStack: UIView!
    @IBOutlet weak var lightningStackWidth: NSLayoutConstraint!
    @IBOutlet weak var boltImage: UIImageView!
    
    // Swap stack
    @IBOutlet weak var swapStack: UIView!
    @IBOutlet weak var swapStackWidth: NSLayoutConstraint!
    @IBOutlet weak var swapImage: UIImageView!
    
    override func awakeFromNib() {
        super.awakeFromNib()
        // Initialization code
        
        // Corner radii
        self.dateView.layer.cornerRadius = 7
        self.gainView.layer.cornerRadius = 7
        self.cardView.layer.cornerRadius = 13
        
        // Button titles
        self.transactionButton.setTitle("", for: .normal)
        
        // Card view styling
        cardView.layer.shadowColor = UIColor.black.cgColor
        cardView.layer.shadowOffset = CGSize(width: 0, height: 8)
        cardView.layer.shadowRadius = 12.0
        cardView.layer.shadowOpacity = 0.05
        
        // Colors
        self.changeColors()
        NotificationCenter.default.addObserver(self, selector: #selector(changeColors), name: NSNotification.Name(rawValue: "changecolors"), object: nil)
    }
    
    func showBittrStack() {
        self.bittrStack.alpha = 1
        NSLayoutConstraint.deactivate([self.bittrStackWidth])
        self.bittrStackWidth = NSLayoutConstraint(item: self.bittrStack, attribute: .width, relatedBy: .greaterThanOrEqual, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 0)
        NSLayoutConstraint.activate([self.bittrStackWidth])
        self.contentView.layoutIfNeeded()
    }
    
    func hideBittrStack() {
        self.bittrStack.alpha = 0
        NSLayoutConstraint.deactivate([self.bittrStackWidth])
        self.bittrStackWidth = NSLayoutConstraint(item: self.bittrStack, attribute: .width, relatedBy: .equal, toItem: nil, attribute: .notAnAttribute, multiplier: 1, constant: 0)
        NSLayoutConstraint.activate([self.bittrStackWidth])
        self.contentView.layoutIfNeeded()
    }
    
    func showLightningStack() {
        self.lightningStack.alpha = 1
        self.lightningStackWidth.constant = 23
    }
    
    func hideLightningStack() {
        self.lightningStack.alpha = 0
        self.lightningStackWidth.constant = 0
    }
    
    func showSwapStack() {
        self.swapStack.alpha = 1
        self.swapStackWidth.constant = 23
    }
    
    func hideSwapStack() {
        self.swapStack.alpha = 0
        self.swapStackWidth.constant = 0
    }
    
    @objc func changeColors() {
        
        cardView.backgroundColor = Colors.getColor("whiteorblue2")
        satsLabel.textColor = Colors.getColor("blackorwhite")
        eurosLabel.textColor = Colors.getColor("blackorwhite")
        dayLabel.textColor = Colors.getColor("blackorwhite")
        dateView.backgroundColor = Colors.getColor("grey1orblue3")
        
        if let actualText = gainLabel.text {
            if actualText.contains("-") {
                // Loss
                gainView.backgroundColor = Colors.getColor("lossbackground")
                arrowImage.tintColor = Colors.getColor("losstext")
                gainLabel.textColor = Colors.getColor("losstext")
            } else {
                // Profit
                gainView.backgroundColor = Colors.getColor("profitbackground")
                arrowImage.tintColor = Colors.getColor("profittext")
                gainLabel.textColor = Colors.getColor("profittext")
            }
        }
        
        if CacheManager.darkModeIsOn() {
            // Dark mode is on.
            bittrImage.image = UIImage(named: "logodarkmode32")
        } else {
            // Dark mode is off.
            bittrImage.image = UIImage(named: "logoorange32")
        }
    }

}
