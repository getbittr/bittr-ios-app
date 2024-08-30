//
//  HistoryTableViewCell.swift
//  bittr
//
//  Created by Tom Melters on 18/04/2023.
//

import UIKit

class HistoryTableViewCell: UITableViewCell {

    @IBOutlet weak var dateView: UIView!
    @IBOutlet weak var dayLabel: UILabel!
    @IBOutlet weak var satsLabel: UILabel!
    @IBOutlet weak var eurosLabel: UILabel!
    @IBOutlet weak var transactionButton: UIButton!
    @IBOutlet weak var cardView: UIView!
    @IBOutlet weak var gainView: UIView!
    @IBOutlet weak var gainLabel: UILabel!
    @IBOutlet weak var arrowImage: UIImageView!
    @IBOutlet weak var bittrImage: UIImageView!
    @IBOutlet weak var boltImage: UIImageView!
    @IBOutlet weak var boltImageTrailing: NSLayoutConstraint!
    
    override func awakeFromNib() {
        super.awakeFromNib()
        // Initialization code
        
        dateView.layer.cornerRadius = 7
        gainView.layer.cornerRadius = 7
        cardView.layer.cornerRadius = 13
        transactionButton.setTitle("", for: .normal)
        
        cardView.layer.shadowColor = UIColor.black.cgColor
        cardView.layer.shadowOffset = CGSize(width: 0, height: 8)
        cardView.layer.shadowRadius = 12.0
        cardView.layer.shadowOpacity = 0.05
        
        self.changeColors()
        
        NotificationCenter.default.addObserver(self, selector: #selector(changeColors), name: NSNotification.Name(rawValue: "changecolors"), object: nil)
    }
    
    func updateBoltTrailing(position:String) {
        
        switch position {
        case "left":
            NSLayoutConstraint.deactivate([self.boltImageTrailing])
            self.boltImageTrailing = NSLayoutConstraint(item: self.boltImage, attribute: .trailing, relatedBy: .equal, toItem: self.bittrImage, attribute: .leading, multiplier: 1, constant: -6)
            NSLayoutConstraint.activate([self.boltImageTrailing])
        case "right":
            NSLayoutConstraint.deactivate([self.boltImageTrailing])
            self.boltImageTrailing = NSLayoutConstraint(item: self.boltImage, attribute: .trailing, relatedBy: .equal, toItem: self.cardView, attribute: .trailing, multiplier: 1, constant: -15)
            NSLayoutConstraint.activate([self.boltImageTrailing])
        default:
            NSLayoutConstraint.deactivate([self.boltImageTrailing])
            self.boltImageTrailing = NSLayoutConstraint(item: self.boltImage, attribute: .trailing, relatedBy: .equal, toItem: self.cardView, attribute: .trailing, multiplier: 1, constant: -15)
            NSLayoutConstraint.activate([self.boltImageTrailing])
        }
    }
    
    @objc func changeColors() {
        
        cardView.backgroundColor = Colors.getColor(color: "cardview")
        satsLabel.textColor = Colors.getColor(color: "black")
        eurosLabel.textColor = Colors.getColor(color: "black")
        dayLabel.textColor = Colors.getColor(color: "black")
        dateView.backgroundColor = Colors.getColor(color: "dateview")
        
        if let actualText = gainLabel.text {
            if actualText.contains("-") {
                // Loss
                gainView.backgroundColor = Colors.getColor(color: "lossbackground")
                arrowImage.tintColor = Colors.getColor(color: "losstext")
                gainLabel.textColor = Colors.getColor(color: "losstext")
            } else {
                // Profit
                gainView.backgroundColor = Colors.getColor(color: "profitbackground")
                arrowImage.tintColor = Colors.getColor(color: "profittext")
                gainLabel.textColor = Colors.getColor(color: "profittext")
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
