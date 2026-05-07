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
        
        // Corner radii.
        self.settingsCardView.layer.cornerRadius = 13
        self.settingsCardView.setShadow()
        
        // Button titles.
        self.settingsButton.setTitle("", for: .normal)
        
        // Notification observers.
        NotificationCenter.default.addObserver(self, selector: #selector(changeColors), name: NSNotification.Name(rawValue: "changecolors"), object: nil)
        
        // Set colors.
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
        
        self.settingsCardLabel.textColor = Colors.getColor("blackorwhite")
        self.settingsCardView.backgroundColor = Colors.getColor("whiteorblue2")
        self.currencyLabel.textColor = Colors.getColor("blackorwhite")
    }

}
