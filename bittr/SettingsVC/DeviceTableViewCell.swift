//
//  DeviceTableViewCell.swift
//  bittr
//
//  Created by Tom Melters on 1/19/26.
//

import UIKit

class DeviceTableViewCell: UITableViewCell {
    
    // UI elements
    @IBOutlet weak var cellCard: UIView!
    @IBOutlet weak var cellIcon: UIImageView!
    @IBOutlet weak var cellTitle: UILabel!
    @IBOutlet weak var buttonLabel: UILabel!
    @IBOutlet weak var cellButton: UIButton!
    @IBOutlet weak var cellSpinner: UIActivityIndicatorView!
    
    // Dark mode
    @IBOutlet weak var darkModeView: UIView!
    @IBOutlet weak var imageSun: UIImageView!
    @IBOutlet weak var imageMoon: UIImageView!
    @IBOutlet weak var imageDevice: UIImageView!
    
    // Variables
    var deviceVC:DeviceViewController?
    
    override func awakeFromNib() {
        super.awakeFromNib()
        
        // Button titles.
        self.cellButton.setTitle("", for: .normal)
        
        // Corner radii.
        self.cellCard.layer.cornerRadius = 13
        
        // Set colors.
        self.changeColors()
    }
    
    @IBAction func cellTapped(_ sender: UIButton) {
        switch sender.accessibilityIdentifier! {
        case "language":
            self.deviceVC?.changeLanguage()
        case "devicetoken":
            self.deviceVC?.getToken()
        case "publickey":
            self.deviceVC?.getPublicKey()
        case "bittrpeer":
            self.deviceVC?.checkPeerConnection()
            self.deviceVC?.tappedCell = self
        case "purchases":
            self.deviceVC?.checkPurchases()
            self.deviceVC?.tappedCell = self
        case "notification":
            self.deviceVC?.checkNotification()
        case "lightningchannels":
            self.deviceVC?.checkChannels()
        case "cache":
            self.deviceVC?.imagesButtonTapped()
        default: return
        }
    }
    
    func animateCell() {
        self.cellSpinner.startAnimating()
        self.buttonLabel.alpha = 0
    }
    
    func stopAnimating() {
        self.cellSpinner.stopAnimating()
        self.buttonLabel.alpha = 1
    }
    
    func changeColors() {
        
        self.cellCard.backgroundColor = Colors.getColor("white0.7orblue2")
        self.cellIcon.tintColor = UIColor(red: 248/255, green: 199/255, blue: 68/255, alpha: 1)
        self.cellTitle.textColor = Colors.getColor("blackorwhite")
        self.buttonLabel.textColor = Colors.getColor("blackorwhite")
        self.cellSpinner.color = Colors.getColor("blackorwhite")
    }
}

enum DarkMode {
    case light
    case dark
    case device
}
