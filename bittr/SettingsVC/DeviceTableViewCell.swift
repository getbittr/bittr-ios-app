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
    @IBOutlet weak var buttonSun: UIButton!
    @IBOutlet weak var buttonMoon: UIButton!
    @IBOutlet weak var buttonDevice: UIButton!
    
    // Variables
    var deviceVC:DeviceViewController?
    
    override func awakeFromNib() {
        super.awakeFromNib()
        
        // Button titles.
        self.cellButton.setTitle("", for: .normal)
        self.buttonSun.setTitle("", for: .normal)
        self.buttonMoon.setTitle("", for: .normal)
        self.buttonDevice.setTitle("", for: .normal)
        
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
            self.deviceVC?.tappedCell = self
            self.deviceVC?.checkPeerConnection()
        case "purchases":
            self.deviceVC?.tappedCell = self
            self.deviceVC?.checkPurchases()
        case "notification":
            self.deviceVC?.checkNotification()
        case "lightningchannels":
            self.deviceVC?.checkChannels()
        case "cache":
            self.deviceVC?.imagesButtonTapped()
        case "pendingpayouts":
            self.deviceVC?.tappedCell = self
            self.deviceVC?.checkPendingPayout()
        default: return
        }
    }
    
    @IBAction func darkModeTapped(_ sender: UIButton) {
        
        self.imageSun.tintColor = Colors.getColor("blackorwhite")
        self.imageMoon.tintColor = Colors.getColor("blackorwhite")
        self.imageDevice.tintColor = Colors.getColor("blackorwhite")
        
        switch sender.tag {
        case 0:
            self.imageSun.tintColor = Colors.getColor("yellow")
            CacheManager.updateDarkMode(.light)
        case 1:
            self.imageMoon.tintColor = Colors.getColor("yellow")
            CacheManager.updateDarkMode(.dark)
        case 2:
            self.imageDevice.tintColor = Colors.getColor("yellow")
            CacheManager.updateDarkMode(.device)
        default: break
        }
        
        CacheManager.setCurrentDarkMode(darkModeIsOn: self.deviceVC!.darkModeIsOn())
        
        NotificationCenter.default.post(NSNotification(name: NSNotification.Name(rawValue: "changecolors"), object: nil, userInfo: nil) as Notification)
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
    
    func showDarkMode() {
        self.cellButton.alpha = 0
        self.darkModeView.alpha = 1
        
        self.imageSun.tintColor = Colors.getColor("blackorwhite")
        self.imageMoon.tintColor = Colors.getColor("blackorwhite")
        self.imageDevice.tintColor = Colors.getColor("blackorwhite")
        
        switch CacheManager.darkMode() {
        case .light:
            self.imageSun.tintColor = Colors.getColor("yellow")
        case .dark:
            self.imageMoon.tintColor = Colors.getColor("yellow")
        case .device:
            self.imageDevice.tintColor = Colors.getColor("yellow")
        }
    }
    
    func hideDarkMode() {
        self.cellButton.alpha = 1
        self.darkModeView.alpha = 0
    }
}

enum DarkMode {
    case light
    case dark
    case device
}
