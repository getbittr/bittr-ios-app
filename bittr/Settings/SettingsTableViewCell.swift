//
//  SettingsTableViewCell.swift
//  bittr
//
//  Created by Tom Melters on 18/05/2023.
//

import UIKit

class SettingsTableViewCell: UITableViewCell {

    @IBOutlet weak var settingsCardView: UIView!
    @IBOutlet weak var settingsCardImage: UIImageView!
    @IBOutlet weak var settingsCardLabel: UILabel!
    @IBOutlet weak var settingsButton: UIButton!
    @IBOutlet weak var currencyLabel: UILabel!
    
    override func awakeFromNib() {
        super.awakeFromNib()
        
        settingsCardView.layer.cornerRadius = 13
        settingsCardView.layer.shadowColor = UIColor.black.cgColor
        settingsCardView.layer.shadowOffset = CGSize(width: 0, height: 7)
        settingsCardView.layer.shadowRadius = 10.0
        settingsCardView.layer.shadowOpacity = 0.07
        
        settingsButton.setTitle("", for: .normal)
        
        NotificationCenter.default.addObserver(self, selector: #selector(changeCurrency), name: NSNotification.Name(rawValue: "changecurrency"), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(changeColors), name: NSNotification.Name(rawValue: "changecolors"), object: nil)
        
        self.changeColors()
    }
    
    @objc func changeCurrency(notification:NSNotification) {
        
        if self.currencyLabel.text != "" {
            if let userInfo = notification.userInfo as [AnyHashable:Any]? {
                if let newCurrency = userInfo["currency"] as? String {
                    self.currencyLabel.text = newCurrency
                }
            }
        }
    }
    
    @objc func changeColors() {
        
        self.settingsCardLabel.textColor = Colors.getColor(color: "black")
        self.settingsCardView.backgroundColor = Colors.getColor(color: "cardview")
        self.currencyLabel.textColor = Colors.getColor(color: "black")
    }

}
